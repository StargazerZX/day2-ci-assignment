#!/usr/bin/env bash
# Stop one PodPoll environment:  local/down.sh dev
set -euo pipefail
cd "$(dirname "$0")/.."
ENV_NAME="${1:-dev}"
[[ $# -gt 0 ]] && shift
docker compose -p "podpoll-${ENV_NAME}" -f local/compose.yaml down "$@"
