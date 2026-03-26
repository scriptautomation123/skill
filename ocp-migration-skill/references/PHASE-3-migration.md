# Phase 3 — Code Migration

Working directory: `./workspace/app`
Source of truth: `{REFERENCE_PROJECT_PATH}`

**Rule:** Apply ONLY what the reference project demonstrates.
**Rule:** Show unified diff before/after for every file modified.
**Rule:** `dc.yaml` and `config.yaml` — verify they exist, make NO changes.

---

## Step 3.1 — Verify dc.yaml and config.yaml (no changes)

```bash
ls ./workspace/app/openshift/dc.yaml    || echo "[MANUAL REQUIRED] dc.yaml not found at openshift/dc.yaml"
ls ./workspace/app/openshift/config.yaml || echo "[MANUAL REQUIRED] config.yaml not found at openshift/config.yaml"
```

If missing: log `[MANUAL REQUIRED]`, add to state, continue — do not block.

---

## Step 3.2 — Root pom.xml

Read reference project root `pom.xml`. Extract:
- Spring Boot parent `<version>`
- Any additional BOM versions
- Plugin versions

Apply to `./workspace/app/pom.xml`:

```xml
<!-- 1. Java version — all four properties required -->
<properties>
  <java.version>21</java.version>
  <maven.compiler.source>21</maven.compiler.source>
  <maven.compiler.target>21</maven.compiler.target>
  <maven.compiler.release>21</maven.compiler.release>
</properties>

<!-- 2. Spring Boot parent — version from reference project -->
<parent>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-parent</artifactId>
  <version><!-- COPY from reference --></version>
</parent>

<!-- 3. Compiler plugin -->
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-compiler-plugin</artifactId>
  <version>3.13.0</version>
  <configuration>
    <release>21</release>
  </configuration>
</plugin>
```

REMOVE any of these if present:
- `wildfly-bom` import
- `jboss-eap-jakartaee-bom` import
- `jboss-parent` reference
- Any `<dependency>` with `groupId` starting with `org.jboss` or `org.wildfly`

---

## Step 3.3 — Controller module pom.xml

Read reference `controller/pom.xml`. Apply:

```xml
<!-- Packaging: WAR → JAR -->
<packaging>jar</packaging>

<!-- Tomcat: remove <scope>provided</scope> so it becomes embedded -->
<!-- BEFORE: -->
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-tomcat</artifactId>
  <scope>provided</scope>   <!-- REMOVE this line -->
</dependency>

<!-- AFTER: no scope = compile/runtime = embedded -->
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-tomcat</artifactId>
</dependency>
```

Remove if present:
- `src/main/webapp/WEB-INF/jboss-web.xml`
- `src/main/webapp/WEB-INF/jboss-deployment-structure.xml`

---

## Step 3.4 — javax.* → jakarta.* migration

```bash
# Apply workspace-wide
find ./workspace/app/src -name "*.java" \
  -exec sed -i 's/import javax\./import jakarta\./g' {} +

# Verify no javax. imports remain (except Java SE packages)
grep -r "import javax\." ./workspace/app/src \
  --include="*.java" \
  | grep -v "javax\.crypto\." \
  | grep -v "javax\.net\." \
  | grep -v "javax\.security\.auth\." \
  | grep -v "javax\.sql\." \
  | grep -v "javax\.xml\.crypto\."
```

If any non-exempt `javax.` imports remain after substitution → log each file,
attempt a second pass, add to `[MANUAL REQUIRED]` if still present.

---

## Step 3.5 — Jenkinsfile

Read reference `Jenkinsfile`. Apply verbatim any changes to:
- Maven/Gradle invocation commands (Java 21 flags)
- Build agent / Docker image reference (must use UBI9 JDK 21)
- Properties/env file path references (must use `sec-{appName}-{dc}.properties`)

DO NOT change unless reference project explicitly shows the change:
- credentials bindings
- notification stages
- SCM / checkout steps
- deployment trigger logic

---

## Step 3.6 — deployment.yaml

Read reference `openshift/deployment.yaml`. Apply probe and resource patterns:

```yaml
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 10
  failureThreshold: 3
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 20
  failureThreshold: 3
resources:
  requests:
    cpu: "250m"
    memory: "512Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"
```

Secret volume mounts are added in Phase 5 after OCP secrets are created.

---

## Step 3.7 — Compile verification

```bash
cd ./workspace/app
mvn compile -B 2>&1 | tail -30

ON FAIL: → Error Handler (classify as compile error)
```

## State update

```json
{
  "currentPhase": 3,
  "completedPhases": [0, 1, 2, 3]
}
```

**EXIT CONDITION:** `mvn compile -B` exits 0.
Log: `[PHASE 3 COMPLETE]`
