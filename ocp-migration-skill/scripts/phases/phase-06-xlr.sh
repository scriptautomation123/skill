#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_env XLR_BASE_URL
require_env XLR_TEMPLATE_NAME
require_env XLR_USER
require_env XLR_API_TOKEN
run_phase_command 6 "PHASE_6_CMD"
