# Phase 0 — Bootstrap & Auth Verification

Read state file first. This phase populates the foundational fields.

## Required inputs (from .env or user-supplied)

```
APP_NAME              appName in state
DC                    dc in state

JIRA_BASE_URL
JIRA_PROJECT_KEY
JIRA_USER
JIRA_API_TOKEN        never log

BITBUCKET_BASE_URL
BITBUCKET_PROJECT
BITBUCKET_USER
BITBUCKET_TOKEN       never log

JENKINS_BASE_URL
JENKINS_JOB_PATH
JENKINS_USER
JENKINS_API_TOKEN     never log

XLR_BASE_URL
XLR_TEMPLATE_NAME
XLR_FOLDER
XLR_USER
XLR_API_TOKEN         never log

OCP_LOGIN_URL
OCP_LOGIN_TOKEN       never log
OCP_NAMESPACE

REFERENCE_PROJECT_PATH
LOCAL_APP_PORT        default 8080
```

If any required input is missing → HALT and list exactly which are absent.

---

## Step 0.1 — Load .env

```bash
set -a && source .env && set +a
echo "Parameters loaded: APP_NAME=${APP_NAME} DC=${DC}"
```

---

## Step 0.2 — Verify Jira

```
GET {JIRA_BASE_URL}/rest/api/3/myself
Headers: Authorization: Basic base64({JIRA_USER}:{JIRA_API_TOKEN})
Expected: HTTP 200
ON FAIL: HALT — "Jira auth failed. Check JIRA_USER / JIRA_API_TOKEN."
```

---

## Step 0.3 — Discover Bitbucket repos (API v1)

Try to derive repo slugs from naming convention before falling back to search.

**Attempt auto-derive first:**
```
REPO_SLUG_APP     = {APP_NAME}
REPO_SLUG_SECRETS = sec-{APP_NAME}-{DC}
REPO_SLUG_CERTS   = sec-{APP_NAME}-certs
REPO_SLUG_XLR     = xlr-config-{APP_NAME}
```

**Verify each exists (API v1):**
```
GET {BITBUCKET_BASE_URL}/rest/api/1.0/projects/{BITBUCKET_PROJECT}/repos/{slug}
Expected: HTTP 200

ON 404 for any slug:
  GET {BITBUCKET_BASE_URL}/rest/api/1.0/projects/{BITBUCKET_PROJECT}/repos?limit=100
  Search for slugs matching:
    APP:     contains APP_NAME, does not start with "sec-", does not contain "xlr"
    SECRETS: starts with "sec-", contains APP_NAME, contains DC
    CERTS:   starts with "sec-", contains APP_NAME, contains "cert"
    XLR:     contains "xlr", contains APP_NAME

  IF still unresolvable: list all slugs found, HALT and ask user to identify missing repo
```

Store resolved slugs in state:
```json
{
  "repoSlugApp":     "...",
  "repoSlugSecrets": "...",
  "repoSlugCerts":   "...",
  "repoSlugXlr":     "..."
}
```

---

## Step 0.4 — Verify Jenkins

```
GET {JENKINS_BASE_URL}/job/{JENKINS_JOB_PATH}/api/json
Expected: HTTP 200
ON FAIL: HALT — "Jenkins auth failed or job path incorrect."
```

---

## Step 0.5 — Verify XLR

```
GET {XLR_BASE_URL}/api/v1/templates
Expected: HTTP 200
Confirm: XLR_TEMPLATE_NAME present in response list
ON FAIL: HALT — "XLR auth failed or template '{XLR_TEMPLATE_NAME}' not found."
```

---

## Step 0.6 — OCP login

Session is NOT pre-established. Agent must log in.

```bash
oc login {OCP_LOGIN_URL} --token={OCP_LOGIN_TOKEN}
oc project {OCP_NAMESPACE}
oc whoami

ON FAIL: HALT — "OCP login failed.
  Obtain a fresh token from: {OCP_LOGIN_URL}/oauth/token/request
  Then update OCP_LOGIN_TOKEN in .env"
```

---

## Step 0.7 — Clone all four repos

```bash
BB_HTTP="{BITBUCKET_BASE_URL}/scm/{BITBUCKET_PROJECT}"

mkdir -p ./workspace
git clone ${BB_HTTP}/{repoSlugApp}.git      ./workspace/app
git clone ${BB_HTTP}/{repoSlugSecrets}.git  ./workspace/secrets
git clone ${BB_HTTP}/{repoSlugCerts}.git    ./workspace/certs
git clone ${BB_HTTP}/{repoSlugXlr}.git      ./workspace/xlr

ON ANY FAIL: HALT — "Clone failed for {repo}.
  Check BITBUCKET_USER / BITBUCKET_TOKEN and repo access."
```

---

## Step 0.8 — Read reference project

```bash
ls {REFERENCE_PROJECT_PATH}/pom.xml
ON FAIL: HALT — "Reference project not found at REFERENCE_PROJECT_PATH."
```

Scan and log what was found:
```bash
echo "Reference files found:"
find {REFERENCE_PROJECT_PATH} -type f \
  \( -name "pom.xml" -o -name "Jenkinsfile" \
     -o -name "xlr-config.json" -o -name "*.properties" \
     -o -name "*.env" -o -name "*.jks" \
     -o -name "*.yaml" -o -name "*.yml" \) \
  | sort
```

Log: `Reference project scanned — {N} files found.`

---

## State update

Write to `.migration-state.json`:
```json
{
  "appName": "{APP_NAME}",
  "dc": "{DC}",
  "repoSlugApp": "...",
  "repoSlugSecrets": "...",
  "repoSlugCerts": "...",
  "repoSlugXlr": "...",
  "currentPhase": 0,
  "completedPhases": [0]
}
```

**EXIT CONDITION:** All eight steps passed, state written.
Log: `[PHASE 0 COMPLETE]`
