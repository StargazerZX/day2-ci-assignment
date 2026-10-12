#!/usr/bin/env bash
# Reference fix for seed 03: after REVIEWING the finding, suppress exactly that finding, with a reason.
# Gitleaks reads .gitleaksignore (one fingerprint per line) from the repository root.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=labs/_lib.sh
source labs/_lib.sh
ensure_tools
report="$(mktemp)"
gitleaks git . --redact --no-banner --exit-code 0 --report-format json --report-path "$report" >/dev/null 2>&1
mapfile -t FPS < <(jq -r '.[] | select(.File == "local/sample/cache.ini") | .Fingerprint' "$report")
[[ ${#FPS[@]} -gt 0 ]] || die "gitleaks reports nothing in local/sample/cache.ini: nothing to suppress"
{
  echo "# Reviewed $(date -u +%Y-%m-%d): local/sample/cache.ini holds a content hash of a public file, not a secret."
  printf '%s\n' "${FPS[@]}"
} >> .gitleaksignore
git add .gitleaksignore
git commit -q -m "lab 03: suppress the reviewed false positive (content hash, not a secret)"
echo "Added ${#FPS[@]} fingerprint(s) to .gitleaksignore with a justification."
