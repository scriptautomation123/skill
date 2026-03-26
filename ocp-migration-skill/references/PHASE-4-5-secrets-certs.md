# Phase 4 — Secrets Repo: Verify Properties & Env Files

Working directory: `./workspace/secrets`
Read state for `appName`, `dc`, `issueKey`.

Files expected:
```
PROPS_FILE = sec-{appName}-{dc}.properties
ENV_FILE   = sec-{appName}-{dc}.env
```

**Rule:** These files should already exist. The agent verifies and aligns keys.
It does NOT create secrets from scratch or populate real values.
All missing values get `REPLACE_ME` and are logged as `[REPLACE_ME]`.

---

## Step 4.1 — Confirm files exist

```bash
ls ./workspace/secrets/sec-${APP_NAME}-${DC}.properties || PROPS_MISSING=1
ls ./workspace/secrets/sec-${APP_NAME}-${DC}.env        || ENV_MISSING=1
```

If missing:
- Create the file from reference project template (keys only, all values `REPLACE_ME`)
- Log: `[MANUAL REQUIRED] sec-{appName}-{dc}.properties was absent — created from template. All values are REPLACE_ME.`
- Add to `state.manualRequired[]`

---

## Step 4.2 — Align keys from reference project

Read all keys from `{REFERENCE_PROJECT_PATH}/sec-*-${DC}.properties`.
For each key not present in `./workspace/secrets/sec-{appName}-{dc}.properties`:
```bash
echo "{missing.key}=REPLACE_ME" >> ./workspace/secrets/sec-${APP_NAME}-${DC}.properties
echo "[REPLACE_ME] {missing.key} in sec-{appName}-{dc}.properties"
```
Add each to `state.replaceMeKeys[]`.

Repeat for `.env`.

---

## Step 4.3 — Ensure TLS properties present

The properties file MUST contain these keys. Add with `REPLACE_ME` if absent:

```properties
server.ssl.enabled=true
server.ssl.key-store=file:/app/config/tls/sec-{appName}-keystore.jks
server.ssl.key-store-password=${KEYSTORE_PASSWORD}
server.ssl.key-store-type=JKS
server.ssl.key-alias=${KEY_ALIAS}
server.ssl.trust-store=file:/app/config/tls/sec-{appName}-truststore.jks
server.ssl.trust-store-password=${TRUSTSTORE_PASSWORD}
```

---

## Step 4.4 — Ensure actuator properties present

```properties
management.endpoints.web.exposure.include=health,info,metrics,env,mappings
management.endpoint.health.probes.enabled=true
management.endpoint.health.show-details=always
management.health.livenessState.enabled=true
management.health.readinessState.enabled=true
management.server.port=8081
spring.profiles.active=${SPRING_PROFILES_ACTIVE:default}
```

---

## Step 4.5 — Commit if changes made

```bash
cd ./workspace/secrets
git diff --stat

if ! git diff --quiet; then
  git add sec-${APP_NAME}-${DC}.properties sec-${APP_NAME}-${DC}.env
  git commit -m "{issueKey} Align sec files for Java 21 / Spring Boot 3 migration"
  git push origin HEAD
fi
```

## State update

```json
{
  "currentPhase": 4,
  "completedPhases": [0,1,2,3,4]
}
```

**EXIT CONDITION:** Both files exist with all required keys.
Log: `[PHASE 4 COMPLETE] {N} keys verified, {M} flagged REPLACE_ME`

---

# Phase 5 — Certs Repo: Read Keystores & Create OCP Secrets

Working directory: `./workspace/certs`
Read state for `appName`, `dc`, `OCP_NAMESPACE`.

---

## Step 5.1 — Locate JKS files

```bash
find ./workspace/certs -name "sec-${APP_NAME}*.jks" | sort
```

Expected:
- `sec-{appName}-keystore.jks`
- `sec-{appName}-truststore.jks`

If either is missing:
```
HALT — "{filename} not found in certs repo.
  TLS cannot proceed. Provide the JKS file and re-run from Phase 5."
```

---

## Step 5.2 — Read keystore alias (no password logging)

```bash
keytool -list \
  -keystore ./workspace/certs/sec-${APP_NAME}-keystore.jks \
  -storepass:env KEYSTORE_PASSWORD \
  -v 2>/dev/null | grep "Alias name:"
```

Store the primary alias → `state.keyAlias`.

If `KEYSTORE_PASSWORD` env var is not set:
```
[MANUAL REQUIRED] Set KEYSTORE_PASSWORD in .env to read keystore alias.
KEY_ALIAS will default to "{appName}-tls" — verify this is correct.
```
Default `state.keyAlias = "{appName}-tls"` and continue.

---

## Step 5.3 — Create OCP JKS secret

```bash
oc create secret generic sec-${APP_NAME}-${DC}-jks \
  --from-file=keystore.jks=./workspace/certs/sec-${APP_NAME}-keystore.jks \
  --from-file=truststore.jks=./workspace/certs/sec-${APP_NAME}-truststore.jks \
  --namespace={OCP_NAMESPACE} \
  --dry-run=client -o yaml | oc apply -f -

oc get secret sec-${APP_NAME}-${DC}-jks -n {OCP_NAMESPACE}
```

---

## Step 5.4 — Create OCP properties secret

```bash
oc create secret generic sec-${APP_NAME}-${DC}-props \
  --from-file=application.properties=./workspace/secrets/sec-${APP_NAME}-${DC}.properties \
  --from-env-file=./workspace/secrets/sec-${APP_NAME}-${DC}.env \
  --namespace={OCP_NAMESPACE} \
  --dry-run=client -o yaml | oc apply -f -

oc get secret sec-${APP_NAME}-${DC}-props -n {OCP_NAMESPACE}
```

---

## Step 5.5 — Add secret mounts to deployment.yaml

Add to `./workspace/app/openshift/deployment.yaml`:

```yaml
# Under spec.template.spec.containers[0].env — append:
- name: KEYSTORE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: sec-{appName}-{dc}-jks
      key: keystore-password
- name: TRUSTSTORE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: sec-{appName}-{dc}-jks
      key: truststore-password
- name: KEY_ALIAS
  value: "{keyAlias}"
- name: SPRING_PROFILES_ACTIVE
  value: "{dc}"

# Under spec.template.spec.containers[0].volumeMounts — append:
- name: tls-keystores
  mountPath: /app/config/tls
  readOnly: true
- name: app-props
  mountPath: /app/config
  readOnly: true

# Under spec.template.spec.volumes — append:
- name: tls-keystores
  secret:
    secretName: sec-{appName}-{dc}-jks
- name: app-props
  secret:
    secretName: sec-{appName}-{dc}-props
```

## State update

```json
{
  "keyAlias": "...",
  "currentPhase": 5,
  "completedPhases": [0,1,2,3,4,5]
}
```

**EXIT CONDITION:** Both OCP secrets confirmed present, deployment.yaml updated.
Log: `[PHASE 5 COMPLETE]`
