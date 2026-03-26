# Phase 1 — Jira: Find the In Development Ticket

Read state. Load `appName`, `dc`, `JIRA_*` vars from .env.

## Step 1.1 — Query

```
GET {JIRA_BASE_URL}/rest/api/3/search
  ?jql=project={JIRA_PROJECT_KEY} AND status="In Development"
  &fields=summary,assignee,issuetype,status
  &maxResults=50
  &orderBy=updated DESC
```

## Step 1.2 — Select

| Result count | Action |
|---|---|
| Exactly 1 | Use it. Log: `TICKET: {issueKey} — {summary}` |
| > 1 | HALT. List all. Prompt: `"Multiple tickets found. Provide ISSUE_KEY to continue."` |
| 0 | HALT. `"No tickets In Development in project {JIRA_PROJECT_KEY}."` |

## Step 1.3 — Derive naming tokens

```
issueKey   = e.g. PAY-412
issueSummary = full summary text
issueSlug  = {issueKey}-{summary → lowercase, spaces→hyphens, strip special chars, max 40 chars}
             e.g. PAY-412-migrate-to-spring-boot3-java21-openshift
branchName = feature/{issueSlug}
```

## State update

```json
{
  "issueKey": "...",
  "issueSummary": "...",
  "issueSlug": "...",
  "branchName": "...",
  "currentPhase": 1,
  "completedPhases": [0, 1]
}
```

**EXIT CONDITION:** `issueKey`, `issueSlug`, `branchName` set in state.
Log: `[PHASE 1 COMPLETE] {issueKey}`

---

# Phase 2 — Bitbucket: Create Feature Branch

Read state. Use `repoSlugApp`, `branchName`, `BITBUCKET_*` vars.
All calls use **Bitbucket Server API v1**.

## Step 2.1 — Get default branch

```
GET {BITBUCKET_BASE_URL}/rest/api/1.0/projects/{BITBUCKET_PROJECT}
    /repos/{repoSlugApp}/branches/default
STORE → state.defaultBranch = response.displayId
```

## Step 2.2 — Create branch

```
POST {BITBUCKET_BASE_URL}/rest/api/1.0/projects/{BITBUCKET_PROJECT}
     /repos/{repoSlugApp}/branches
Content-Type: application/json
Body:
{
  "name": "{branchName}",
  "startPoint": "refs/heads/{defaultBranch}"
}
Expected: HTTP 200 or 201
ON FAIL: HALT — log response body for diagnosis
```

## Step 2.3 — Checkout locally

```bash
cd ./workspace/app
git fetch origin
git checkout -b {branchName} origin/{defaultBranch}
git status
```

## State update

```json
{
  "defaultBranch": "...",
  "currentPhase": 2,
  "completedPhases": [0, 1, 2]
}
```

**EXIT CONDITION:** Branch confirmed in Bitbucket, checked out in `./workspace/app`.
Log: `[PHASE 2 COMPLETE] Branch: {branchName}`
