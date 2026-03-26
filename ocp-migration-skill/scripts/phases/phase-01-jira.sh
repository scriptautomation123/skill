#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_env JIRA_BASE_URL
require_env JIRA_PROJECT_KEY
require_env JIRA_USER
require_env JIRA_API_TOKEN

run_phase_command 1 "PHASE_1_CMD"
