# Error Classifications

Used by the Error Handler in SKILL.md. Match the error to its classification,
then apply the targeted fix and re-run from the phase entry point.

---

## Compile error
**Symptoms:** `mvn compile` or `mvn package` exits non-zero, `BUILD FAILURE`
in output, Java compiler errors in log.

**Common causes:**
- `javax.*` import not replaced with `jakarta.*`
- Incompatible API removed in Java 21 (e.g. `SecurityManager`)
- Spring Boot 3 class renames (e.g. `SpringBootServletInitializer` moved package)
- Dependency version incompatible with Java 21

**Fix:**
1. Read the full compiler error — note the file and line number
2. For `javax.` → `jakarta.` misses: re-run the sed pass on the specific file
3. For removed APIs: check Spring Boot 3 migration guide for replacement
4. For dependency issues: check reference project's pom.xml for the correct version
5. Re-run from Phase 3 start

---

## Local boot failure
**Symptoms:** Health check returns non-UP, app process exits within 30s,
connection refused on LOCAL_APP_PORT.

**Common causes:**
- `REPLACE_ME` values in sec- env file causing startup failure
- TLS config error (ignore if `--server.ssl.enabled=false` is set)
- Spring profile mismatch (app expects a profile that doesn't exist locally)
- Port conflict

**Fix:**
1. Check startup log: `java -jar ... 2>&1 | head -100`
2. If REPLACE_ME values are the cause: log `[MANUAL REQUIRED]`, use stub values locally only
3. If port conflict: change `LOCAL_APP_PORT` in .env
4. Re-run from Phase 7 start

---

## Jenkins build failure
**Symptoms:** Jenkins result == "FAILURE" or "ABORTED".

**Common causes:**
- Maven compile failure in Jenkins environment (may differ from local Java version)
- Image build failure (Dockerfile, registry auth)
- Test failures
- Jenkins agent doesn't have Java 21 toolchain

**Fix:**
1. Read console log — identify the first `ERROR` or `FAILED` line
2. For compile failures: fix source, push amendment commit, re-trigger
3. For image push failures: check registry credentials in Jenkins credentials store
4. For test failures: fix the test or the implementation
5. Re-run from Phase 8.2 (push) — do not re-commit if no code changes

---

## OCP image missing
**Symptoms:** `oc get istag` returns not found after successful Jenkins build.

**Common causes:**
- Jenkins pipeline did not complete the image push step
- Image pushed to wrong namespace or tag format
- ImageStream does not exist yet

**Fix:**
1. Check Jenkins console for image push step output
2. Verify `oc get imagestream {appName} -n {OCP_NAMESPACE}` — create if absent
3. Check the image tag format used by Jenkins matches `{issueKey}-{buildNumber}`
4. Log `[MANUAL REQUIRED]` with exact push command for team to verify
5. Re-run from Phase 9.2

---

## OCP pod crash / rollout timeout
**Symptoms:** `oc rollout status` times out, pods in `CrashLoopBackOff` or
`Error`, rollout does not complete.

**Common causes:**
- Missing OCP secret (sec-*-jks or sec-*-props not applied in Phase 5)
- Wrong secret key name in deployment.yaml volume mount
- App startup fails due to TLS config (keystore path wrong)
- Readiness probe path incorrect (app doesn't expose `/actuator/health/readiness`)
- Insufficient memory limit

**Fix:**
1. Read pod logs: `oc logs {pod} -n {OCP_NAMESPACE} --tail=200`
2. Read pod describe: `oc describe pod {pod} -n {OCP_NAMESPACE}`
3. For secret mount errors: verify `oc get secret sec-{appName}-{dc}-jks -n {OCP_NAMESPACE}`
4. For TLS errors: confirm keystore path in properties file matches mountPath
5. For probe 404: confirm `management.endpoints.web.exposure.include` contains `health`
6. Re-run from Phase 9.3 after fix

---

## OCP health probe failure
**Symptoms:** Route reachable but `/actuator/health` returns non-200 or
`{"status":"DOWN"}`.

**Common causes:**
- Database or downstream dependency unreachable from OCP namespace
- TLS handshake failure (keystore loaded but cert not trusted)
- Spring profile not activating correctly (DC-specific config not loaded)
- Actuator health indicator failing on a non-critical dependency

**Fix:**
1. `GET /actuator/health` — read the full response body, not just `.status`
2. Identify which component shows DOWN
3. For DB: check OCP network policy allows pod → DB connectivity
4. For TLS: verify KEY_ALIAS matches the alias in the keystore
5. For profile: verify `SPRING_PROFILES_ACTIVE` env var is set correctly on the pod
6. Re-run from Phase 9.6 after fix — no need to re-rollout unless config changed

---

## Smoke test 401 / 403
**Symptoms:** Endpoints return 401 Unauthorized or 403 Forbidden in OCP but
returned 200 locally.

**Common causes:**
- Spring Security configured differently for prod profile vs local
- OAuth2 / JWT token required in prod environment
- CSRF protection active on GET endpoints (unusual but possible)

**Fix:**
1. Check if endpoint requires auth header — try with Bearer token if applicable
2. Update `smoke-test-endpoints.json` expectedStatus to 401 for secured endpoints
3. Log `[MANUAL REQUIRED]` if endpoint requires auth the agent cannot provide
4. Re-run Phase 10 smoke tests

---

## Smoke test 404
**Symptoms:** Endpoints return 404 in OCP but 200 locally.

**Common causes:**
- `server.servlet.context-path` set differently in prod properties
- Endpoint path includes a path variable with no default
- Different Spring profile disables a feature/endpoint

**Fix:**
1. `GET /actuator/mappings` — compare against local mappings
2. If context-path differs: prefix all paths in smoke-test-endpoints.json
3. Remove endpoints that genuinely don't exist in prod from smoke-test-endpoints.json
4. Re-run Phase 10 smoke tests

---

## Smoke test 5xx
**Symptoms:** Endpoints return 500/502/503 in OCP.

**Common causes:**
- Unhandled exception on startup request
- Backend service unreachable
- Database connection pool exhausted
- Missing environment variable causing NullPointerException

**Fix:**
1. Read pod logs immediately after the 5xx: `oc logs -f -l app={appName} -n {OCP_NAMESPACE}`
2. Identify the exception class and message
3. Fix the root cause (missing config, network, etc.)
4. Re-run from Phase 9.3 if config change required, or Phase 10 if fix is deployed
