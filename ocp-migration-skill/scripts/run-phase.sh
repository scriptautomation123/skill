#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/state.sh"

PHASE=""
ENV_FILE="${ROOT_DIR}/.env"
WORKSPACE_ROOT="${ROOT_DIR}"
STATE_FILE="${ROOT_DIR}/workspace/.migration-state.json"
RESUME="false"

usage() {
  cat <<EOF
Usage:
  bash scripts/run-phase.sh --phase <0..10|all> [--resume] [--env-file <path>] [--state-file <path>] [--workspace-root <path>]

Examples:
  bash scripts/run-phase.sh --phase 0 --env-file ./.env --state-file ./workspace/.migration-state.json --workspace-root .
  bash scripts/run-phase.sh --phase all --resume --env-file ./.env --state-file ./workspace/.migration-state.json --workspace-root .
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --workspace-root) WORKSPACE_ROOT="$2"; shift 2 ;;
    --resume) RESUME="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "$EX_USAGE" "Unknown argument: $1" ;;
  esac
done

[[ -n "$PHASE" ]] || die "$EX_USAGE" "--phase is required"

require_cmd jq
require_cmd bash

safe_source_env_file "$ENV_FILE"
export STATE_FILE
state_init
state_read

MAX_RETRY="${MAX_RETRY:-3}"

phase_script() {
  local p="$1"
  case "$p" in
    0)  echo "${SCRIPT_DIR}/phases/phase-00-bootstrap.sh" ;;
    1)  echo "${SCRIPT_DIR}/phases/phase-01-jira.sh" ;;
    2)  echo "${SCRIPT_DIR}/phases/phase-02-bitbucket.sh" ;;
    3)  echo "${SCRIPT_DIR}/phases/phase-03-migration.sh" ;;
    4)  echo "${SCRIPT_DIR}/phases/phase-04-secrets.sh" ;;
    5)  echo "${SCRIPT_DIR}/phases/phase-05-certs.sh" ;;
    6)  echo "${SCRIPT_DIR}/phases/phase-06-xlr.sh" ;;
    7)  echo "${SCRIPT_DIR}/phases/phase-07-local.sh" ;;
    8)  echo "${SCRIPT_DIR}/phases/phase-08-jenkins.sh" ;;
    9)  echo "${SCRIPT_DIR}/phases/phase-09-ocp.sh" ;;
    10) echo "${SCRIPT_DIR}/phases/phase-10-smoke.sh" ;;
    *) die "$EX_USAGE" "Invalid phase: ${p}" ;;
  esac
}

run_one_phase() {
  local p="$1"
  local script
  script="$(phase_script "$p")"
  [[ -f "$script" ]] || die "$EX_UNIMPL" "Phase script missing: ${script}"

  export CURRENT_PHASE="$p"
  local attempt=1

  while (( attempt <= MAX_RETRY )); do
    phase_start "$p"
    if bash "$script" "$ENV_FILE" "$STATE_FILE" "$WORKSPACE_ROOT"; then
      state_phase_complete "$p"
      phase_complete "$p"
      return 0
    fi

    local rc=$?
    phase_failed "$p"

    if is_retryable_code "$rc" && (( attempt < MAX_RETRY )); then
      log_warn "Phase ${p} failed with rc=${rc}, retry ${attempt}/${MAX_RETRY}"
      attempt=$((attempt + 1))
      continue
    fi

    state_blocker "Phase ${p} failed rc=${rc} after ${attempt} attempt(s)."
    return "$rc"
  done
}

run_all_phases() {
  local start=0
  if [[ "$RESUME" == "true" ]]; then
    local current
    current="$(jq -r '.currentPhase // 0' "$STATE_FILE")"
    if [[ "$current" =~ ^[0-9]+$ ]] && (( current >= 0 && current < 10 )); then
      start=$((current + 1))
    fi
  fi

  local p
  for (( p=start; p<=10; p++ )); do
    run_one_phase "$p" || return $?
  done
}

if [[ "$PHASE" == "all" ]]; then
  run_all_phases
else
  [[ "$PHASE" =~ ^([0-9]|10)$ ]] || die "$EX_USAGE" "--phase must be 0..10 or all"
  run_one_phase "$PHASE"
fi

state_summary
