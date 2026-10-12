#!/usr/bin/env bash
# Pre-build security scans: Gitleaks (git history), TruffleHog (git history) and Trivy (filesystem:
# vulnerable dependencies, secrets, misconfigurations such as Dockerfiles and Kubernetes manifests).
#
# Used by .github/prescan/action.yml in CI, and runnable locally (labs/scan-local.sh does that):
#   SCAN_TARGET=. REPORT_DIR=reports .github/prescan/scan.sh
#
# Environment:
#   SCAN_TARGET       repository to scan (default: $GITHUB_WORKSPACE, else the current directory)
#   REPORT_DIR        where the JSON reports go (default: current directory)
#   TRIVY_SEVERITY    severities that count as BLOCKING for Trivy (default: CRITICAL,HIGH)
#   FAIL_ON_FINDINGS  true = exit 1 when there are blocking findings (default: false, report only)
#
# What counts as BLOCKING (and is listed in the summary):
#   gitleaks    every finding (fix it, or suppress that one finding with a justification)
#   trufflehog  VERIFIED secrets only (it proved the credential works); unverified ones are reported
#   trivy       vulnerabilities at TRIVY_SEVERITY that HAVE a fix, plus misconfigurations and secrets at
#               TRIVY_SEVERITY. Suppressed findings (.trivyignore.yaml / .gitleaksignore) don't block.
# Reports never contain the secret itself: Gitleaks runs with --redact, TruffleHog's raw values are stripped.
set -uo pipefail

TARGET="${SCAN_TARGET:-}"
[[ -z "$TARGET" ]] && TARGET="${GITHUB_WORKSPACE:-$PWD}"
OUT="${REPORT_DIR:-.}"
SEVERITY="${TRIVY_SEVERITY:-CRITICAL,HIGH}"
FAIL="${FAIL_ON_FINDINGS:-false}"
mkdir -p "$OUT"
GL="$OUT/gitleaks-report.json"
TH="$OUT/trufflehog-report.json"
TV="$OUT/trivy-report-prescan.json"
TOOL_ERRORS=0

echo "::group::Gitleaks (git history of $TARGET)"
# --exit-code 0: findings don't stop the script; we decide below. A real error still returns non-zero.
if ! gitleaks git "$TARGET" --redact --no-banner --exit-code 0 --report-format json --report-path "$GL"; then
  echo "::error::gitleaks failed to run"; TOOL_ERRORS=$((TOOL_ERRORS + 1)); echo '[]' > "$GL"
fi
echo "::endgroup::"

echo "::group::TruffleHog (git history of $TARGET)"
# Every result (verified, unknown, unverified) goes in the report; raw secret values are removed.
if trufflehog git "file://$TARGET" --json --no-update --results=verified,unknown,unverified 2>/dev/null > "$TH.raw"; then
  jq -c 'select(.DetectorName) | del(.Raw, .RawV2, .Redacted, .SecretParts)' "$TH.raw" > "$TH"
else
  echo "::error::trufflehog failed to run"; TOOL_ERRORS=$((TOOL_ERRORS + 1)); : > "$TH"
fi
rm -f "$TH.raw"
echo "::endgroup::"

echo "::group::Trivy filesystem (vuln, secret, misconfig) on $TARGET"
IGNORE=()
[[ -f "$TARGET/.trivyignore.yaml" ]] && IGNORE=(--ignorefile "$TARGET/.trivyignore.yaml")
[[ -f "$TARGET/.trivyignore" ]] && IGNORE=(--ignorefile "$TARGET/.trivyignore")
if ! trivy fs --quiet --scanners vuln,secret,misconfig --show-suppressed "${IGNORE[@]}" \
      --format json --output "$TV" "$TARGET"; then
  echo "::error::trivy failed to run"; TOOL_ERRORS=$((TOOL_ERRORS + 1)); echo '{}' > "$TV"
fi
echo "::endgroup::"

# ---- count -------------------------------------------------------------------------------------
SEV_JSON="$(jq -cn --arg s "$SEVERITY" '$s | ascii_upcase | split(",")')"
gl_total=$(jq 'length' "$GL")
th_verified=$(jq -s '[.[] | select(.Verified == true)] | length' "$TH")
th_unverified=$(jq -s '[.[] | select(.Verified != true)] | length' "$TH")
tv_vuln=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Vulnerabilities[]? | select(.Severity as $x | $s | index($x)) | select((.FixedVersion // "") != "")] | length' "$TV")
tv_unfixed=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Vulnerabilities[]? | select(.Severity as $x | $s | index($x)) | select((.FixedVersion // "") == "")] | length' "$TV")
tv_misconf=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Misconfigurations[]? | select(.Status == "FAIL") | select(.Severity as $x | $s | index($x))] | length' "$TV")
tv_secret=$(jq --argjson s "$SEV_JSON" '[.Results[]?.Secrets[]? | select(.Severity as $x | $s | index($x))] | length' "$TV")
tv_suppressed=$(jq '[.Results[]?.ExperimentalModifiedFindings[]?] | length' "$TV")
tv_other=$(jq --argjson s "$SEV_JSON" '([.Results[]?.Vulnerabilities[]?, .Results[]?.Misconfigurations[]?, .Results[]?.Secrets[]?] | map(select(.Severity as $x | ($s | index($x)) | not)) | length)' "$TV")
blocking=$((gl_total + th_verified + tv_vuln + tv_misconf + tv_secret))

# ---- details of what blocks, so nobody has to open the JSON to find out --------------------------
details() {
  jq -r '.[] | "  gitleaks    \(.RuleID)  \(.File):\(.StartLine)  commit \(.Commit[0:7])"' "$GL"
  jq -r 'select(.Verified == true) | "  trufflehog  VERIFIED \(.DetectorName)  \(.SourceMetadata.Data.Git.file // "?"):\(.SourceMetadata.Data.Git.line // "?")"' "$TH"
  jq -r --argjson s "$SEV_JSON" '.Results[]? | .Target as $t |
      ((.Vulnerabilities // [])[] | select(.Severity as $x | $s | index($x)) | select((.FixedVersion // "") != "")
        | "  trivy       \(.Severity) \(.VulnerabilityID)  \(.PkgName) \(.InstalledVersion) -> \(.FixedVersion)  (\($t))"),
      ((.Misconfigurations // [])[] | select(.Status == "FAIL") | select(.Severity as $x | $s | index($x))
        | "  trivy       \(.Severity) \(.ID)  \(.Title)  (\($t))"),
      ((.Secrets // [])[] | select(.Severity as $x | $s | index($x))
        | "  trivy       \(.Severity) secret \(.RuleID)  \($t):\(.StartLine)")' "$TV"
}

SUMMARY="$(cat <<MD
### Pre-build security scan

| Tool | Blocking | Also reported |
|---|---:|---|
| Gitleaks (history) | ${gl_total} | |
| TruffleHog (history) | ${th_verified} verified | ${th_unverified} unverified |
| Trivy fs (${SEVERITY}) | $((tv_vuln + tv_misconf + tv_secret)) (vuln ${tv_vuln}, misconfig ${tv_misconf}, secret ${tv_secret}) | ${tv_unfixed} without a fix yet, ${tv_other} at lower severity, ${tv_suppressed} suppressed |
MD
)"
echo "$SUMMARY"
if (( blocking > 0 )); then
  echo; echo "Blocking findings:"; details
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  { echo "$SUMMARY"; if (( blocking > 0 )); then echo; echo '```text'; details; echo '```'; fi; } >> "$GITHUB_STEP_SUMMARY"
fi
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  { echo "blocking-findings=$blocking"; echo "gitleaks-findings=$gl_total"
    echo "trufflehog-verified=$th_verified"; echo "trufflehog-unverified=$th_unverified"
    echo "trivy-blocking=$((tv_vuln + tv_misconf + tv_secret))"; } >> "$GITHUB_OUTPUT"
fi

if (( TOOL_ERRORS > 0 )); then
  echo "::error::${TOOL_ERRORS} scanner(s) failed to run: the scan is incomplete"; exit 2
fi
if (( blocking > 0 )); then
  if [[ "$FAIL" == "true" ]]; then
    echo "::error::${blocking} blocking security finding(s)"; exit 1
  fi
  echo "::warning::${blocking} blocking security finding(s) (fail-on-findings is off, so the job stays green)"
fi
exit 0
