#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd oc
require_env OCP_LOGIN_URL
require_env OCP_LOGIN_TOKEN
require_env OCP_NAMESPACE
run_phase_command 9 "PHASE_9_CMD"
