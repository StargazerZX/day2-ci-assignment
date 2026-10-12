#!/usr/bin/env bash
# Post-build security scan: Trivy on a built container image (OS packages, language packages,
# secrets baked into layers, image misconfigurations).
#
# Used by .github/postscan/action.yml in CI, and runnable locally:
#   IMAGE=podpoll-api:2.0 REPORT_DIR=reports .github/postscan/scan-image.sh
#
# Environment:
#   IMAGE             image reference to scan (required): a local image or a registry reference
#   REPORT_DIR        where the JSON report goes (default: current directory)
#   REPORT_FILE       report file name (default: trivy-report-postscan.json)
#   TRIVY_SEVERITY    severities that count as BLOCKING (default: CRITICAL,HIGH)
#   IGNORE_FILE       optional .trivyignore.yaml with accepted risks (default: ./.trivyignore.yaml if present)
#   FAIL_ON_FINDINGS  true = exit 1 on blocking findings (default: false, report only)
# BLOCKING = vulnerabilities at TRIVY_SEVERITY that have a fix, plus secrets/misconfigs at TRIVY_SEVERITY.
set -uo pipefail
: "${IMAGE:?set IMAGE to the image to scan}"
OUT="${REPORT_DIR:-.}"
FILE="${REPORT_FILE:-trivy-report-postscan.json}"
SEVERITY="${TRIVY_SEVERITY:-CRITICAL,HIGH}"
FAIL="${FAIL_ON_FINDINGS:-false}"
IGNORE_FILE="${IGNORE_FILE:-}"
[[ -z "$IGNORE_FILE" && -f .trivyignore.yaml ]] && IGNORE_FILE=.trivyignore.yaml
mkdir -p "$OUT"
TV="$OUT/$FILE"

IGNORE=()
[[ -n "$IGNORE_FILE" ]] && IGNORE=(--ignorefile "$IGNORE_FILE")
echo "::group::Trivy image scan of $IMAGE"
if ! trivy image --quiet --scanners vuln,secret,misconfig --show-suppressed "${IGNORE[@]}" \
      --format json --output "$TV" "$IMAGE"; then
  echo "::error::trivy failed to scan $IMAGE"; echo "::endgroup::"; exit 2
fi
echo "::endgroup::"

SEV_JSON="$(jq -cn --arg s "$SEVERITY" '$s | ascii_upcase | split(",")')"
vuln=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Vulnerabilities[]? | select(.Severity as $x | $s | index($x)) | select((.FixedVersion // "") != "")] | length' "$TV")
unfixed=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Vulnerabilities[]? | select(.Severity as $x | $s | index($x)) | select((.FixedVersion // "") == "")] | length' "$TV")
other=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Vulnerabilities[]?, .Results[]?.Misconfigurations[]?, .Results[]?.Secrets[]? | select(.Severity as $x | ($s | index($x)) | not)] | length' "$TV")
misconf=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Misconfigurations[]? | select(.Status == "FAIL") | select(.Severity as $x | $s | index($x))] | length' "$TV")
secret=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Secrets[]? | select(.Severity as $x | $s | index($x))] | length' "$TV")
suppressed=$(jq '[.Results[]?.ExperimentalModifiedFindings[]?] | length' "$TV")
os=$(jq -r '.Metadata.OS | if . then "\(.Family) \(.Name)" else "unknown OS" end' "$TV")
blocking=$((vuln + misconf + secret))

details() {
  jq -r --argjson s "$SEV_JSON" '.Results[]? | .Target as $t |
      ((.Vulnerabilities // [])[] | select(.Severity as $x | $s | index($x)) | select((.FixedVersion // "") != "")
        | "  \(.Severity) \(.VulnerabilityID)  \(.PkgName) \(.InstalledVersion) -> \(.FixedVersion)  (\($t))"),
      ((.Misconfigurations // [])[] | select(.Status == "FAIL") | select(.Severity as $x | $s | index($x))
        | "  \(.Severity) \(.ID)  \(.Title)"),
      ((.Secrets // [])[] | select(.Severity as $x | $s | index($x)) | "  \(.Severity) secret \(.RuleID)  \($t)")' "$TV" | sort -u | head -40
}

SUMMARY="$(cat <<MD
### Image scan: \`${IMAGE}\` (${os})

| Blocking (${SEVERITY}, fixable) | Also reported |
|---:|---|
| ${blocking} (vuln ${vuln}, misconfig ${misconf}, secret ${secret}) | ${unfixed} without a fix yet, ${other} at lower severity, ${suppressed} suppressed |
MD
)"
echo "$SUMMARY"
if (( blocking > 0 )); then echo; echo "Blocking findings (first 40):"; details; fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  { echo "$SUMMARY"; if (( blocking > 0 )); then echo; echo '```text'; details; echo '```'; fi; } >> "$GITHUB_STEP_SUMMARY"
fi
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "blocking-findings=$blocking" >> "$GITHUB_OUTPUT"

if (( blocking > 0 )); then
  if [[ "$FAIL" == "true" ]]; then echo "::error::${blocking} blocking finding(s) in ${IMAGE}"; exit 1; fi
  echo "::warning::${blocking} blocking finding(s) in ${IMAGE} (fail-on-findings is off, so the job stays green)"
fi
exit 0
