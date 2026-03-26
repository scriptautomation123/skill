#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_env APP_NAME
require_env DC
require_cmd git
require_cmd oc

run_phase_command 0 "PHASE_0_CMD"
