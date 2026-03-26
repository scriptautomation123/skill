#!/usr/bin/env bash
# state.sh — read and write .migration-state.json
# Usage:
#   source scripts/state.sh
#   state_read                          # loads all state vars into env
#   state_write key value               # sets a single key
#   state_append_array key "value"      # appends to a JSON array key
#   state_phase_complete N              # marks phase N complete

STATE_FILE="${STATE_FILE:-./workspace/.migration-state.json}"

state_init() {
  if [ ! -f "$STATE_FILE" ]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" <<'EOF'
{
  "appName":            "",
  "dc":                 "",
  "issueKey":           "",
  "issueSummary":       "",
  "issueSlug":          "",
  "branchName":         "",
  "defaultBranch":      "",
  "repoSlugApp":        "",
  "repoSlugSecrets":    "",
  "repoSlugCerts":      "",
  "repoSlugXlr":        "",
  "xlrReleaseId":       "",
  "buildNumber":        "",
  "ocpBaseUrl":         "",
  "keyAlias":           "",
  "smokeEndpointCount": 0,
  "currentPhase":       0,
  "completedPhases":    [],
  "manualRequired":     [],
  "replaceMeKeys":      [],
  "blockers":           []
}
EOF
    echo "[STATE] Initialised new state file: $STATE_FILE"
  fi
}

state_read() {
  if [ ! -f "$STATE_FILE" ]; then state_init; fi

  export APP_NAME=$(jq -r '.appName'        "$STATE_FILE")
  export DC=$(jq -r '.dc'                   "$STATE_FILE")
  export ISSUE_KEY=$(jq -r '.issueKey'      "$STATE_FILE")
  export ISSUE_SLUG=$(jq -r '.issueSlug'    "$STATE_FILE")
  export BRANCH_NAME=$(jq -r '.branchName'  "$STATE_FILE")
  export DEFAULT_BRANCH=$(jq -r '.defaultBranch' "$STATE_FILE")
  export REPO_SLUG_APP=$(jq -r '.repoSlugApp'     "$STATE_FILE")
  export REPO_SLUG_SECRETS=$(jq -r '.repoSlugSecrets' "$STATE_FILE")
  export REPO_SLUG_CERTS=$(jq -r '.repoSlugCerts'   "$STATE_FILE")
  export REPO_SLUG_XLR=$(jq -r '.repoSlugXlr'       "$STATE_FILE")
  export XLR_RELEASE_ID=$(jq -r '.xlrReleaseId'     "$STATE_FILE")
  export BUILD_NUMBER=$(jq -r '.buildNumber'         "$STATE_FILE")
  export OCP_BASE_URL=$(jq -r '.ocpBaseUrl'          "$STATE_FILE")
  export KEY_ALIAS=$(jq -r '.keyAlias'               "$STATE_FILE")
  export CURRENT_PHASE=$(jq -r '.currentPhase'       "$STATE_FILE")

  echo "[STATE] Loaded — phase: $CURRENT_PHASE, issue: $ISSUE_KEY, branch: $BRANCH_NAME"
}

state_write() {
  local KEY="$1"
  local VALUE="$2"
  local TMP=$(mktemp)
  jq --arg k "$KEY" --arg v "$VALUE" '.[$k] = $v' "$STATE_FILE" > "$TMP"
  mv "$TMP" "$STATE_FILE"
}

state_write_int() {
  local KEY="$1"
  local VALUE="$2"
  local TMP=$(mktemp)
  jq --arg k "$KEY" --argjson v "$VALUE" '.[$k] = $v' "$STATE_FILE" > "$TMP"
  mv "$TMP" "$STATE_FILE"
}

state_append_array() {
  local KEY="$1"
  local VALUE="$2"
  local TMP=$(mktemp)
  jq --arg k "$KEY" --arg v "$VALUE" '.[$k] += [$v]' "$STATE_FILE" > "$TMP"
  mv "$TMP" "$STATE_FILE"
  echo "[STATE] Appended to ${KEY}: ${VALUE}"
}

state_phase_complete() {
  local PHASE="$1"
  local TMP=$(mktemp)
  jq --argjson p "$PHASE" '
    .currentPhase = $p |
    .completedPhases = (.completedPhases + [$p] | unique | sort)
  ' "$STATE_FILE" > "$TMP"
  mv "$TMP" "$STATE_FILE"
  echo "[PHASE ${PHASE} COMPLETE]"
}

state_blocker() {
  local MSG="$1"
  state_append_array "blockers" "$MSG"
  echo "[BLOCKER] $MSG"
}

state_manual_required() {
  local MSG="$1"
  state_append_array "manualRequired" "$MSG"
  echo "[MANUAL REQUIRED] $MSG"
}

state_replace_me() {
  local KEY="$1"
  local FILE="$2"
  state_append_array "replaceMeKeys" "${KEY} in ${FILE}"
  echo "[REPLACE_ME] ${KEY} in ${FILE}"
}

state_summary() {
  echo ""
  echo "=============================================================="
  echo "MIGRATION SUMMARY — $(jq -r '.appName' $STATE_FILE) [$(jq -r '.dc' $STATE_FILE)] — $(jq -r '.issueKey' $STATE_FILE)"
  echo "=============================================================="
  echo "Branch:        $(jq -r '.branchName' $STATE_FILE)"
  echo "Jenkins build: #$(jq -r '.buildNumber' $STATE_FILE)"
  echo "XLR release:   $(jq -r '.xlrReleaseId' $STATE_FILE)"
  echo "OCP URL:       $(jq -r '.ocpBaseUrl' $STATE_FILE)"
  echo "Completed:     $(jq -r '.completedPhases | join(", ")' $STATE_FILE)"
  echo ""
  echo "[MANUAL REQUIRED]"
  jq -r '.manualRequired[] | "  - " + .' "$STATE_FILE"
  echo ""
  echo "[REPLACE_ME — set before prod deploy]"
  jq -r '.replaceMeKeys[] | "  - " + .' "$STATE_FILE"
  echo ""
  echo "[BLOCKERS]"
  jq -r '.blockers[] | "  - " + .' "$STATE_FILE"
  echo "=============================================================="
}
