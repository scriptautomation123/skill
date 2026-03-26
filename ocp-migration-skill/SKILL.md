---
name: ocp-migration
description: >
  End-to-end migration and deployment agent for upgrading a Java/JBoss application
  to Spring Boot 3 + Java 21 + embedded Tomcat and deploying it to OpenShift.
  Orchestrates across four separate repos (app, secrets, certs, XLR), drives
  Jira, Bitbucket API v1, Jenkins, XL Release, and the oc CLI. Use this skill
  whenever the user wants to migrate a JBoss app to OpenShift, run the full
  deployment pipeline, resume a stalled migration, run smoke tests against OCP,
  or generate an XLR release config for a Spring Boot migration. Also triggers
  for partial runs: branch creation only, endpoint discovery only, or
  post-deploy smoke testing only.
---

# OCP Migration Skill

Orchestrates a 10-phase migration pipeline. Each phase has a blocking exit
condition. State is persisted to `.migration-state.json` so any phase can be
resumed independently.

## How to use this skill

Read this file first. Then read the specific reference file for the phase
you are about to execute. Do not load all reference files upfront.

All phase execution MUST happen through `scripts/run-phase.sh` (or
`scripts/run-phase.ps1` on Windows). The AI orchestrates and validates; scripts
perform operational commands.

**Full pipeline trigger:**
```
@workspace Run the OCP migration pipeline. Parameters are in .env at repo root.
Reference project is at {REFERENCE_PROJECT_PATH}.
```

**Partial run triggers:**
```
Resume from Phase {N} — state is in .migration-state.json
Run Phase 7 only — endpoint discovery for {APP_NAME}
Run Phase 10 only — smoke tests against {OCP_BASE_URL}
```

**Execution contract:**
```bash
# single phase
bash scripts/run-phase.sh --phase {N} --env-file ./.env --state-file ./workspace/.migration-state.json --workspace-root .

# full run from beginning
bash scripts/run-phase.sh --phase all --env-file ./.env --state-file ./workspace/.migration-state.json --workspace-root .

# full run resume
bash scripts/run-phase.sh --phase all --resume --env-file ./.env --state-file ./workspace/.migration-state.json --workspace-root .
```

```powershell
./scripts/run-phase.ps1 -Phase {N} -EnvFile ./.env -StateFile ./workspace/.migration-state.json -WorkspaceRoot .
./scripts/run-phase.ps1 -Phase all -Resume -EnvFile ./.env -StateFile ./workspace/.migration-state.json -WorkspaceRoot .
```

---

## State File Contract

The agent MUST read `.migration-state.json` at the start of every run and
write it after every phase completes. This is the single source of truth
for all computed values. Never carry state in conversational memory alone.

**Location:** `./workspace/.migration-state.json`

**Schema:**
```json
{
  "appName":           "",
  "dc":                "",
  "issueKey":          "",
  "issueSummary":      "",
  "issueSlug":         "",
  "branchName":        "",
  "defaultBranch":     "",
  "repoSlugApp":       "",
  "repoSlugSecrets":   "",
  "repoSlugCerts":     "",
  "repoSlugXlr":       "",
  "xlrReleaseId":      "",
  "buildNumber":       "",
  "ocpBaseUrl":        "",
  "keyAlias":          "",
  "smokeEndpointCount": 0,
  "currentPhase":      0,
  "completedPhases":   [],
  "manualRequired":    [],
  "replaceMeKeys":     [],
  "blockers":          []
}
```

**Rules:**
- Read state at phase start: `cat ./workspace/.migration-state.json`
- Write state at phase end: update the relevant fields, persist the file
- Never hardcode a value that could be read from state
- If state file is absent, start from Phase 0

---

## Phase Map

| Phase | Name | Reference File | Key Output |
|---|---|---|---|
| 0 | Bootstrap & auth | `references/PHASE-0-bootstrap.md` | all repos cloned, OCP logged in |
| 1 | Jira ticket | `references/PHASE-1-2-jira-bitbucket.md` | `issueKey`, `branchName` |
| 2 | Bitbucket branch | `references/PHASE-1-2-jira-bitbucket.md` | branch created and checked out |
| 3 | Code migration | `references/PHASE-3-migration.md` | code compiles on Java 21 |
| 4 | Secrets repo | `references/PHASE-4-5-secrets-certs.md` | sec- files verified, keys aligned |
| 5 | Certs + OCP secrets | `references/PHASE-4-5-secrets-certs.md` | OCP secrets applied |
| 6 | XLR config | `references/PHASE-6-xlr.md` | `xlrReleaseId` |
| 7 | Local verify + endpoints | `references/PHASE-7-local.md` | `smoke-test-endpoints.json` |
| 8 | Commit + Jenkins | `references/PHASE-8-jenkins.md` | `buildNumber` |
| 9 | OCP deploy verify | `references/PHASE-9-10-ocp-smoke.md` | all pods ready, `ocpBaseUrl` |
| 10 | Smoke tests | `references/PHASE-9-10-ocp-smoke.md` | all tests pass, Jira transitioned |

**To execute a phase:**
1. Read state file
2. Read the phase's reference file
3. Execute the corresponding script phase (`scripts/run-phase.sh --phase N ...`)
4. Update state file
5. Log `[PHASE N COMPLETE]` before advancing

---

## Naming Conventions (memorise these — used in every phase)

```
Properties file : sec-{appName}-{dc}.properties          (in REPO_SECRETS)
Env file        : sec-{appName}-{dc}.env                  (in REPO_SECRETS)
Keystore        : sec-{appName}-keystore.jks              (in REPO_CERTS)
Truststore      : sec-{appName}-truststore.jks            (in REPO_CERTS)
OCP secret/JKS  : sec-{appName}-{dc}-jks
OCP secret/props: sec-{appName}-{dc}-props
XLR config      : xlr-config.json                         (in REPO_XLR)
Branch          : feature/{issueKey}-{issueSlug}
OCP app label   : app={appName}
```

---

## Repo Topology

Four separate repos. Never cross-contaminate.

```
REPO_APP      app source, pom.xml, Jenkinsfile, openshift/ manifests
REPO_SECRETS  sec-{appName}-{dc}.properties + .env  — verify/align only
REPO_CERTS    sec-{appName}-*.jks                   — read only, create OCP secrets
REPO_XLR      xlr-config.json                       — generate and push
```

Cross-contamination rules (hard blockers):
- Never commit secrets or JKS files to REPO_APP
- Never commit source code to REPO_SECRETS, REPO_CERTS, or REPO_XLR
- dc.yaml and config.yaml: verify they exist, make NO changes

---

## Error Handler

Invoked when any phase step fails after its retry limit.

```
MAX_RETRY = 3 per step
ATTEMPT   = 0

WHILE ATTEMPT < MAX_RETRY:
  1. Capture full error + last 150 log lines
  2. Classify → see references/ERROR-CLASSIFICATIONS.md
  3. Apply targeted fix in the correct repo
  4. Re-run the failed phase from its entry point
  5. Increment ATTEMPT

IF ATTEMPT == MAX_RETRY:
  Append to state.blockers[]
  Print: "BLOCKED: {error}. Repo: {repo}. Manual action: {step}"
  HALT
```

For error classification details → read `references/ERROR-CLASSIFICATIONS.md`

---

## Output Conventions

```
[PHASE N START]
[PHASE N COMPLETE]
[PHASE N FAILED → error handler]
[SKIP] {step} — {reason}
[MANUAL REQUIRED] {description}      ← collected, printed in end-of-run summary
[REPLACE_ME] {key} in {file}         ← collected, printed in end-of-run summary
```

- Show unified diff for every file modified
- Log METHOD URL HTTP_STATUS for every API call
- Never log credential values
- Log every autonomous decision made

---

## End-of-Run Summary

Always print after Phase 10 (pass or fail):

```
==============================================================
MIGRATION SUMMARY — {appName} [{dc}] — {issueKey}
==============================================================
Branch:        {branchName}
Jenkins build: #{buildNumber}
XLR release:   {xlrReleaseId}
OCP URL:       {ocpBaseUrl}
Smoke tests:   {pass}/{total} passed
Jira:          {transition name or "left In Development"}

[MANUAL REQUIRED]
  {each item from state.manualRequired[]}

[REPLACE_ME — must be set before prod deploy]
  {each item from state.replaceMeKeys[]}

[BLOCKERS]
  {each item from state.blockers[]}
==============================================================
```
