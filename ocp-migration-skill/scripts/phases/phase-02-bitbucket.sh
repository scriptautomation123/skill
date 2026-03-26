#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd git
require_env BITBUCKET_BASE_URL
require_env BITBUCKET_PROJECT
require_env BITBUCKET_USER
require_env BITBUCKET_TOKEN

run_phase_command 2 "PHASE_2_CMD"
