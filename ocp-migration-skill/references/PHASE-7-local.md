# Phase 7 — Local Verification & Read-Only Endpoint Discovery

Working directory: `./workspace/app`
Read state for `appName`, `dc`. Load `LOCAL_APP_PORT` from .env (default 8080).

**Purpose:** Boot the app locally to confirm it starts. Discover all safe
GET endpoints for use as post-OCP smoke tests. TLS is disabled locally
to avoid cert path issues — that is expected and correct.

---

## Step 7.1 — Package

```bash
cd ./workspace/app
mvn package -DskipTests -B 2>&1 | tail -20

ON FAIL: → Error Handler (classify: compile or packaging error)
```

---

## Step 7.2 — Export env and boot

```bash
# Load secrets env (real values must be populated — check REPLACE_ME keys first)
REPLACE_ME_COUNT=$(grep -c "REPLACE_ME" ./workspace/secrets/sec-${APP_NAME}-${DC}.env || true)
if [ "$REPLACE_ME_COUNT" -gt 0 ]; then
  echo "[MANUAL REQUIRED] ${REPLACE_ME_COUNT} REPLACE_ME values in sec-${APP_NAME}-${DC}.env"
  echo "Local boot will attempt to start — some features may fail."
fi

set -a
source ./workspace/secrets/sec-${APP_NAME}-${DC}.env
set +a

java -jar target/*.jar \
  --spring.config.location=./workspace/secrets/sec-${APP_NAME}-${DC}.properties \
  --spring.profiles.active=local \
  --server.ssl.enabled=false \
  --management.server.port=8081 \
  --server.port=${LOCAL_APP_PORT:-8080} &

APP_PID=$!
echo "Started PID: ${APP_PID}"
sleep 25
```

---

## Step 7.3 — Confirm health

```bash
HEALTH=$(curl -sf --max-time 10 \
  http://localhost:${LOCAL_APP_PORT:-8080}/actuator/health \
  | jq -r .status 2>/dev/null)

echo "Health: ${HEALTH}"

if [ "$HEALTH" != "UP" ]; then
  kill $APP_PID 2>/dev/null
  echo "FAIL: Health returned '${HEALTH}' — expected 'UP'"
  → Error Handler (classify: local boot failure)
fi
```

---

## Step 7.4 — Discover all GET endpoints

```bash
curl -sf http://localhost:8081/actuator/mappings \
  | jq '[
      .contexts[].mappings.dispatcherServlets.dispatcherServlet[]
      | select(
          .details.requestMappingConditions.methods != null and
          (.details.requestMappingConditions.methods | contains(["GET"]))
        )
      | {
          path: (.details.requestMappingConditions.patterns[0] // "unknown"),
          methods: .details.requestMappingConditions.methods
        }
    ]
    | unique_by(.path)
    | sort_by(.path)' > /tmp/discovered-endpoints.json

TOTAL=$(cat /tmp/discovered-endpoints.json | jq length)
echo "Discovered ${TOTAL} GET endpoints"
```

---

## Step 7.5 — Filter to safe read-only endpoints

Exclude any path that contains these segments (case-insensitive):
`/delete`, `/remove`, `/update`, `/create`, `/reset`, `/shutdown`,
`/restart`, `/pause`, `/refresh`, `/clear`, `/flush`

Also exclude: `/actuator/shutdown`

```bash
cat /tmp/discovered-endpoints.json \
  | jq '[.[] | select(
      (.path | ascii_downcase |
        test("/delete|/remove|/update|/create|/reset|/shutdown|/restart|/pause|/refresh|/clear|/flush")
      ) | not
    ) | { path: .path, expectedStatus: 200 }]' \
  > ./workspace/app/smoke-test-endpoints.json

SAFE=$(cat ./workspace/app/smoke-test-endpoints.json | jq length)
echo "Safe smoke test endpoints: ${SAFE}"
```

If fewer than 1 endpoint found:
```
[MANUAL REQUIRED] No safe endpoints discovered. Check actuator/mappings is
exposed (management.endpoints.web.exposure.include=mappings) and the app
started correctly.
```

---

## Step 7.6 — Run local smoke pass (informational — does not block)

```bash
PASS=0; WARN=0

for row in $(cat ./workspace/app/smoke-test-endpoints.json | jq -c '.[]'); do
  EP=$(echo $row | jq -r '.path')
  EXPECTED=$(echo $row | jq -r '.expectedStatus')
  ACTUAL=$(curl -o /dev/null -sw "%{http_code}" \
    --max-time 10 "http://localhost:${LOCAL_APP_PORT:-8080}${EP}")
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "PASS | ${EP} → ${ACTUAL}"; ((PASS++))
  else
    echo "WARN | ${EP} → got ${ACTUAL}, expected ${EXPECTED}"; ((WARN++))
  fi
done

kill $APP_PID 2>/dev/null
echo "Local smoke: ${PASS} pass, ${WARN} warn (warns do not block)"
```

---

## State update

```json
{
  "smokeEndpointCount": "{SAFE}",
  "currentPhase": 7,
  "completedPhases": [0,1,2,3,4,5,6,7]
}
```

**EXIT CONDITION:** App booted, health returned `UP`, `smoke-test-endpoints.json`
has ≥ 1 entry.
Log: `[PHASE 7 COMPLETE] {SAFE} smoke test endpoints written`
