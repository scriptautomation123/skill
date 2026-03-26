# Phase 9 — OpenShift Deployment Verification

Read state for `appName`, `dc`, `issueKey`, `buildNumber`.
Load `OCP_*` vars from .env.

---

## Step 9.1 — Re-authenticate if session may have expired

```bash
oc whoami 2>/dev/null \
  || oc login {OCP_LOGIN_URL} --token={OCP_LOGIN_TOKEN}

oc project {OCP_NAMESPACE}
echo "OCP session confirmed: $(oc whoami)"
```

---

## Step 9.2 — Confirm image in registry

```bash
# Try ImageStreamTag first (most common in OCP)
oc get istag ${APP_NAME}:${ISSUE_KEY}-${BUILD_NUMBER} \
  -n {OCP_NAMESPACE} 2>/dev/null \
|| oc get imagestreamtag ${APP_NAME}:${ISSUE_KEY}-${BUILD_NUMBER} \
   -n {OCP_NAMESPACE}

ON FAIL:
  LOG: "Image {appName}:{issueKey}-{buildNumber} not found in {OCP_NAMESPACE}"
  LOG: "Expected push from Jenkins to: {OCP_IMAGE_REGISTRY}/{OCP_NAMESPACE}/{appName}"
  LOG: "Verify Jenkins pipeline image push step completed successfully."
  → Error Handler (classify: OCP image missing)
```

---

## Step 9.3 — Trigger rollout

```bash
# Try DeploymentConfig (dc/) first — common in OCP 3/4 JBoss migrations
oc rollout latest dc/${APP_NAME} -n {OCP_NAMESPACE} 2>/dev/null \
  || oc rollout restart deployment/${APP_NAME} -n {OCP_NAMESPACE}
```

---

## Step 9.4 — Wait for rollout

```bash
# Try DC first, fall back to Deployment
oc rollout status dc/${APP_NAME} -n {OCP_NAMESPACE} --timeout=10m 2>/dev/null \
  || oc rollout status deployment/${APP_NAME} -n {OCP_NAMESPACE} --timeout=10m

ON FAIL:
  oc get pods -n {OCP_NAMESPACE} -l app=${APP_NAME}

  FAILING=$(oc get pods -n {OCP_NAMESPACE} -l app=${APP_NAME} \
    -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==false)].metadata.name}')

  for pod in $FAILING; do
    echo "=== Logs: $pod ==="
    oc logs $pod -n {OCP_NAMESPACE} --tail=150
    echo "=== Describe: $pod ==="
    oc describe pod $pod -n {OCP_NAMESPACE} | tail -30
  done

  → Error Handler (classify: OCP pod crash or rollout timeout)
```

---

## Step 9.5 — Verify ALL pods ready

```bash
EXPECTED=$(oc get deployment ${APP_NAME} -n {OCP_NAMESPACE} \
  -o jsonpath='{.spec.replicas}' 2>/dev/null \
  || oc get dc ${APP_NAME} -n {OCP_NAMESPACE} \
  -o jsonpath='{.spec.replicas}')

READY=$(oc get pods -n {OCP_NAMESPACE} \
  -l app=${APP_NAME} \
  -o json | jq '[.items[] |
    select(.status.containerStatuses != null and
           .status.containerStatuses[0].ready == true)] | length')

echo "Pods: ${READY}/${EXPECTED} ready"

if [ "$READY" -ne "$EXPECTED" ]; then
  echo "FAIL: not all pods ready"
  oc get pods -n {OCP_NAMESPACE} -l app=${APP_NAME}
  → Error Handler
fi
```

---

## Step 9.6 — Confirm route and health

```bash
OCP_ROUTE=$(oc get route ${APP_NAME} -n {OCP_NAMESPACE} \
  -o jsonpath='{.spec.host}')
OCP_BASE_URL="https://${OCP_ROUTE}"

echo "Route: ${OCP_BASE_URL}"

HEALTH=$(curl -sf --max-time 15 \
  "${OCP_BASE_URL}/actuator/health" | jq -r .status)

echo "Health: ${HEALTH}"

if [ "$HEALTH" != "UP" ]; then
  echo "FAIL: Health returned '${HEALTH}'"
  → Error Handler (classify: OCP health probe failure)
fi
```

## State update

```json
{
  "ocpBaseUrl": "...",
  "currentPhase": 9,
  "completedPhases": [0,1,2,3,4,5,6,7,8,9]
}
```

**EXIT CONDITION:** All pods ready, health via route returns `UP`.
Log: `[PHASE 9 COMPLETE] Live at {ocpBaseUrl}`

---

# Phase 10 — Actuator Check & Smoke Tests

Read state for `appName`, `dc`, `issueKey`, `ocpBaseUrl`.
Load `JIRA_*` vars from .env.

---

## Step 10.1 — Enumerate actuator endpoints

```bash
curl -sf "${OCP_BASE_URL}/actuator" | jq '._links | keys[]'
```

Log every endpoint found.

---

## Step 10.2 — Probe core actuator endpoints

```bash
declare -A PROBES=(
  ["/actuator/health"]="200"
  ["/actuator/health/liveness"]="200"
  ["/actuator/health/readiness"]="200"
  ["/actuator/info"]="200"
  ["/actuator/metrics"]="200"
)

for EP in "${!PROBES[@]}"; do
  STATUS=$(curl -o /dev/null -sw "%{http_code}" \
    --max-time 10 "${OCP_BASE_URL}${EP}")
  EXPECTED="${PROBES[$EP]}"
  if [ "$STATUS" = "$EXPECTED" ]; then
    echo "PASS | ${EP} → ${STATUS}"
  else
    echo "WARN | ${EP} → got ${STATUS}, expected ${EXPECTED}"
  fi
done
```

Note: `/actuator/env` and `/actuator/mappings` may return 401 in prod
(security config). That is expected — log the actual status, do not fail.

---

## Step 10.3 — Run smoke tests

```bash
PASS=0; FAIL=0; RESULTS=()

for row in $(cat ./workspace/app/smoke-test-endpoints.json | jq -c '.[]'); do
  EP=$(echo $row | jq -r '.path')
  EXPECTED=$(echo $row | jq -r '.expectedStatus')
  ACTUAL=$(curl -o /dev/null -sw "%{http_code}" \
    --max-time 15 "${OCP_BASE_URL}${EP}")

  if [ "$ACTUAL" = "$EXPECTED" ]; then
    RESULTS+=("PASS | ${EP} | ${ACTUAL}")
    ((PASS++))
  else
    RESULTS+=("FAIL | ${EP} | expected ${EXPECTED} got ${ACTUAL}")
    ((FAIL++))
  fi
done

echo ""
echo "SMOKE TEST RESULTS — ${APP_NAME} [${DC}] on ${OCP_NAMESPACE}"
echo "================================================================"
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "================================================================"
echo "  Total: ${PASS} passed, ${FAIL} failed"
echo ""
```

---

## Step 10.4 — Transition Jira ticket

```
GET {JIRA_BASE_URL}/rest/api/3/issue/{issueKey}/transitions
Find transition named (in order of preference):
  "Ready for Review" → "Code Review" → "In Review" → "Done"
STORE: TRANSITION_ID, TRANSITION_NAME
```

If `FAIL == 0`:
```
POST {JIRA_BASE_URL}/rest/api/3/issue/{issueKey}/transitions
Body: { "transition": { "id": "{TRANSITION_ID}" } }
LOG: "Jira {issueKey} → {TRANSITION_NAME}"
```

If `FAIL > 0`:
```
LOG: "{FAIL} smoke test(s) failed. Jira ticket left In Development."
→ Error Handler (classify: smoke test failure)
```

## State update

```json
{
  "currentPhase": 10,
  "completedPhases": [0,1,2,3,4,5,6,7,8,9,10]
}
```

**EXIT CONDITION:** `FAIL == 0`, Jira transitioned.
Log: `[PHASE 10 COMPLETE] {PASS}/{PASS+FAIL} passed. Jira → {TRANSITION_NAME}`
