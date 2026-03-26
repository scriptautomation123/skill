# Phase 6 — XLR Repo: Generate Release Config

Working directory: `./workspace/xlr`
Read state for all computed values. Load `XLR_*` vars from .env.

---

## Step 6.1 — Read reference xlr-config.json structure

```bash
cat {REFERENCE_PROJECT_PATH}/xlr-config.json | jq .
```

Extract and note:
- All top-level keys
- All variable names inside `variables` block
- Any non-obvious field names specific to your org's XLR template

The generated config must match this structure exactly. Add org-specific
fields from the reference. Do not invent fields not in the reference.

---

## Step 6.2 — Generate xlr-config.json

Write to `./workspace/xlr/xlr-config.json`:

```json
{
  "releaseTitle": "{issueKey} — {issueSummary}",
  "releaseFolder": "{XLR_FOLDER}",
  "templateName": "{XLR_TEMPLATE_NAME}",
  "tags": [
    "{JIRA_PROJECT_KEY}",
    "{appName}",
    "{dc}",
    "java21",
    "spring-boot-3",
    "openshift"
  ],
  "variables": {
    "jiraIssueKey":      "{issueKey}",
    "appName":           "{appName}",
    "dataCentre":        "{dc}",
    "gitBranch":         "{branchName}",
    "bitbucketProject":  "{BITBUCKET_PROJECT}",
    "bitbucketRepo":     "{repoSlugApp}",
    "jenkinsJobPath":    "{JENKINS_JOB_PATH}",
    "ocpNamespace":      "{OCP_NAMESPACE}",
    "imageTag":          "{issueKey}-{BUILD_NUMBER}",
    "springProfile":     "{dc}",
    "propertiesSecret":  "sec-{appName}-{dc}-props",
    "tlsSecret":         "sec-{appName}-{dc}-jks",
    "propsFile":         "sec-{appName}-{dc}.properties",
    "envFile":           "sec-{appName}-{dc}.env"
  }
}
```

Note: `{BUILD_NUMBER}` is a literal placeholder string.
Jenkins resolves it at pipeline runtime via variable injection.

Add any additional fields found in the reference project structure.

---

## Step 6.3 — Commit to XLR repo

```bash
cd ./workspace/xlr
git add xlr-config.json
git commit -m "{issueKey} Generate XLR release config — {appName} [{dc}] Java 21 migration"
git push origin HEAD
```

---

## Step 6.4 — Register release with XLR server

```
POST {XLR_BASE_URL}/api/v1/releases
Content-Type: application/json
Authorization: Basic base64({XLR_USER}:{XLR_API_TOKEN})
Body: contents of xlr-config.json

Expected: HTTP 200 or 201, response.id present
STORE → state.xlrReleaseId = response.id
LOG: "XLR release created: {xlrReleaseId}"
```

## State update

```json
{
  "xlrReleaseId": "...",
  "currentPhase": 6,
  "completedPhases": [0,1,2,3,4,5,6]
}
```

**EXIT CONDITION:** `xlr-config.json` committed, `xlrReleaseId` in state.
Log: `[PHASE 6 COMPLETE] XLR: {xlrReleaseId}`
