#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_env JENKINS_BASE_URL
require_env JENKINS_JOB_PATH
require_env JENKINS_USER
require_env JENKINS_API_TOKEN
run_phase_command 8 "PHASE_8_CMD"
