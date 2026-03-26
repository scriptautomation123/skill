#!/usr/bin/env bash

set -Eeuo pipefail

EX_OK=0
EX_DEP=10
EX_USAGE=11
EX_CONFIG=12
EX_STATE=13
EX_API=20
EX_OCP=21
EX_GIT=22
EX_VALIDATE=23
EX_MANUAL=30
EX_UNIMPL=40
EX_RETRY=50
EX_INTERNAL=99

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

event() {
  local level="$1"
  local phase="$2"
  local code="$3"
  local message="$4"
  echo "EVENT|$(timestamp_utc)|${level}|${phase}|${code}|${message}"
}

log_info() { event "INFO" "${CURRENT_PHASE:-NA}" "0" "$1"; }
log_warn() { event "WARN" "${CURRENT_PHASE:-NA}" "0" "$1"; }
log_error() { event "ERROR" "${CURRENT_PHASE:-NA}" "0" "$1"; }

die() {
  local code="$1"
  local message="$2"
  log_error "$message"
  exit "$code"
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "$EX_DEP" "Required command not found: ${cmd}"
}

require_env() {
  local key="$1"
  local value="${!key:-}"
  [[ -n "$value" ]] || die "$EX_CONFIG" "Missing required env var: ${key}"
}

phase_start() {
  local phase="$1"
  echo "[PHASE ${phase} START]"
}

phase_complete() {
  local phase="$1"
  echo "[PHASE ${phase} COMPLETE]"
}

phase_failed() {
  local phase="$1"
  echo "[PHASE ${phase} FAILED -> error handler]"
}

is_retryable_code() {
  local code="$1"
  case "$code" in
    20|21|22|50) return 0 ;;
    *) return 1 ;;
  esac
}

safe_source_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || die "$EX_CONFIG" "Env file not found: ${env_file}"
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

run_phase_command() {
  local phase="$1"
  local env_key="$2"
  local cmd="${!env_key:-}"

  [[ -n "$cmd" ]] || die "$EX_CONFIG" "${env_key} is not set. Define it in .env"

  log_info "Executing ${env_key}"
  bash -lc "$cmd"
}
