# Phase 8 — Commit, Push & Jenkins Build

Working directory: `./workspace/app`
Read state for all values. Load `JENKINS_*` vars from .env.

---

## Step 8.1 — Stage and commit

```bash
cd ./workspace/app
git add -A
git status

git commit -m "{issueKey} Migrate {appName} to Java 21 + Spring Boot 3 + embedded Tomcat [{dc}]

Changes applied from reference project:
- root pom.xml: Java 21, Spring Boot 3 parent, compiler plugin 3.13.0
- controller/pom.xml: JAR packaging, embedded Tomcat scope removed
- javax.* replaced with jakarta.* (Jakarta EE 10)
- JBoss WEB-INF descriptors removed
- Jenkinsfile: updated per reference project
- deployment.yaml: probes, resource limits, TLS + props secret mounts
- dc.yaml / config.yaml: verified present, no changes
- smoke-test-endpoints.json: {smokeEndpointCount} read-only endpoints

OCP secrets: sec-{appName}-{dc}-jks, sec-{appName}-{dc}-props
XLR release: {xlrReleaseId}
Jira: {issueKey}"
```

---

## Step 8.2 — Push branch

```bash
git push origin {branchName}
```

---

## Step 8.3 — Obtain Jenkins crumb

```bash
CRUMB_JSON=$(curl -sf -u {JENKINS_USER}:{JENKINS_API_TOKEN} \
  "{JENKINS_BASE_URL}/crumbIssuer/api/json")

CRUMB=$(echo $CRUMB_JSON | jq -r '.crumb')
CRUMB_FIELD=$(echo $CRUMB_JSON | jq -r '.crumbRequestField')

echo "Crumb obtained: ${CRUMB_FIELD}=***"
```

---

## Step 8.4 — Trigger build

```bash
HTTP_STATUS=$(curl -o /dev/null -sw "%{http_code}" \
  -X POST \
  -u {JENKINS_USER}:{JENKINS_API_TOKEN} \
  -H "${CRUMB_FIELD}: ${CRUMB}" \
  "{JENKINS_BASE_URL}/job/{JENKINS_JOB_PATH}/buildWithParameters" \
  --data-urlencode "BRANCH_NAME={branchName}" \
  --data-urlencode "APP_NAME={appName}" \
  --data-urlencode "DC={dc}" \
  --data-urlencode "JIRA_ISSUE={issueKey}")

echo "Trigger HTTP status: ${HTTP_STATUS}"

if [ "$HTTP_STATUS" != "201" ] && [ "$HTTP_STATUS" != "200" ]; then
  echo "FAIL: Unexpected trigger status ${HTTP_STATUS}"
  → Error Handler
fi
```

---

## Step 8.5 — Poll for completion

```
TIMEOUT:       30 minutes
POLL INTERVAL: 30 seconds

LOOP:
  GET {JENKINS_BASE_URL}/job/{JENKINS_JOB_PATH}/lastBuild/api/json
  EXTRACT: building, result, number

  IF building == true  → sleep 30, continue
  IF building == false → evaluate result

  ON result == "SUCCESS":
    STORE → state.buildNumber = response.number
    LOG: "Jenkins #{buildNumber} SUCCESS"
    → break loop, proceed to Phase 9

  ON result == "FAILURE" or "ABORTED" or "UNSTABLE":
    GET {JENKINS_BASE_URL}/job/{JENKINS_JOB_PATH}/lastBuild/consoleText
    LOG: last 150 lines
    → Error Handler (classify: Jenkins build failure)

ON TIMEOUT:
  LOG: "Jenkins build did not complete within 30 minutes."
  → Error Handler
```

## State update

```json
{
  "buildNumber": "...",
  "currentPhase": 8,
  "completedPhases": [0,1,2,3,4,5,6,7,8]
}
```

**EXIT CONDITION:** `result == "SUCCESS"`, `buildNumber` in state.
Log: `[PHASE 8 COMPLETE] Jenkins #{buildNumber}`
