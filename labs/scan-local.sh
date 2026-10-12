#!/usr/bin/env bash
# Run the SAME scans as CI, on your machine, with the same tool versions (downloaded and
# checksum-verified the first time into .labs-tools/, which git ignores).
#
#   labs/scan-local.sh                       # prescan: Gitleaks + TruffleHog (history), Trivy (files)
#   labs/scan-local.sh --build frontend      # build an image from frontend/ and postscan it
#   labs/scan-local.sh --image podpoll-api:2.0   # postscan an existing image
#
# Exit code: 0 = no blocking findings, 1 = blocking findings, 2 = a scanner failed to run.
# Reports: reports/local/*.json
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
# shellcheck source=labs/_lib.sh
source labs/_lib.sh
ensure_tools

MODE=prescan IMAGE=""
case "${1:-}" in
  --image) MODE=postscan; IMAGE="${2:?--image needs an image reference}";;
  --build)
    MODE=postscan
    COMPONENT="${2:?--build needs api or frontend}"
    [[ -f "$COMPONENT/Dockerfile" ]] || die "no $COMPONENT/Dockerfile"
    IMAGE="podpoll-${COMPONENT}:scan-local"
    echo "Building $IMAGE from $COMPONENT/ ..."
    docker build -q -t "$IMAGE" "$COMPONENT" >/dev/null || die "docker build failed"
    ;;
  "") ;;
  *) die "usage: labs/scan-local.sh [--build <component> | --image <image>]";;
esac

if [[ "$MODE" == prescan ]]; then
  SCAN_TARGET="$PWD" REPORT_DIR=reports/local FAIL_ON_FINDINGS=true .github/prescan/scan.sh
else
  IMAGE="$IMAGE" REPORT_DIR=reports/local FAIL_ON_FINDINGS=true .github/postscan/scan-image.sh
fi
