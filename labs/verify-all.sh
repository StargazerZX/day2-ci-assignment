#!/usr/bin/env bash
# labs/verify-all.sh [NN ...] -- prove every lab seed behaves as designed, with the CI's tool versions.
#
# For each seed, in a throwaway clone of the current commit (your working copy is never touched):
#   1. plant it, scan it              -> the scanners named in its `expect` file MUST flag it
#   2. apply the reference fix, rescan -> NO blocking findings may remain
# Image seeds (EXPECT_IMAGE) build that component's image and postscan it; seed 08 is checked with ruff.
# Needs: git, jq, docker (image seeds), and uvx or ruff (seed 08). Takes a few minutes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
# shellcheck source=labs/_lib.sh
source labs/_lib.sh
ensure_tools
export LABS_TOOLS_DIR="$TOOLS_DIR"            # clones reuse the downloaded tools
shopt -s nullglob

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SEEDS=("$@")
if [[ ${#SEEDS[@]} -eq 0 ]]; then
  for d in labs/[0-9][0-9]-*/; do d="${d#labs/}"; SEEDS+=("${d:0:2}"); done
fi

# prescan in the current directory; prints "key=value" outputs
prescan_outputs() {
  local out="$WORK/out.$RANDOM"; : > "$out"
  GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY="" SCAN_TARGET="$PWD" REPORT_DIR="$WORK/reports" FAIL_ON_FINDINGS=false \
    .github/prescan/scan.sh >"$WORK/scan.log" 2>&1 || { echo "scan-error=1"; }
  cat "$out"
}
image_blocking() { # component
  local out="$WORK/img.$RANDOM"; : > "$out"
  docker build -q -t "podpoll-$1:verify" "$1" >/dev/null 2>&1 || { echo "build-error"; return; }
  GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY="" IMAGE="podpoll-$1:verify" REPORT_DIR="$WORK/reports" FAIL_ON_FINDINGS=false \
    .github/postscan/scan-image.sh >"$WORK/img.log" 2>&1 || { echo "scan-error"; return; }
  sed -n 's/^blocking-findings=//p' "$out"
}
ruff_codes() {
  if command -v ruff >/dev/null; then ruff check --output-format concise api/ 2>/dev/null
  elif command -v uvx >/dev/null; then uvx --quiet ruff check --output-format concise api/ 2>/dev/null
  else echo "ruff-missing"; fi
}
get() { sed -n "s/^$1=//p" <<<"$2" | tail -1; }

RESULTS=()
FAILED=0
for ID in "${SEEDS[@]}"; do
  dirs=(labs/"${ID}"-*/); [[ ${#dirs[@]} -eq 1 ]] || { RESULTS+=("$ID  ✘ no such seed"); FAILED=1; continue; }
  NAME="${dirs[0]#labs/}"; NAME="${NAME%/}"
  EXPECT_PRESCAN=""; EXPECT_IMAGE=""; EXPECT_RUFF=""
  # shellcheck disable=SC1090
  source "labs/$NAME/expect"
  echo "${C_B}== ${NAME}${C_0}"
  clone="$WORK/$NAME"
  if ! git clone -q "$REPO_ROOT" "$clone" || ! cd "$clone"; then FAILED=1; continue; fi
  git -c advice.detachedHead=false switch -q --detach "$(git -C "$REPO_ROOT" rev-parse HEAD)"
  git switch -q -c verify-base
  git config user.email "labs@verify.invalid"; git config user.name "labs verify"
  ok_seed=1; detail=""

  labs/plant.sh "$ID" >/dev/null || { ok_seed=0; detail+=" plant-failed"; }
  before="$(prescan_outputs)"
  [[ "$(get scan-error "$before")" == 1 ]] && { ok_seed=0; detail+=" prescan-error"; }
  for key in $EXPECT_PRESCAN; do
    v="$(get "$key" "$before")"
    if [[ "${v:-0}" -gt 0 ]]; then detail+=" ${key}=${v}"; else ok_seed=0; detail+=" ${key}=${v:-0}(EXPECTED>0)"; fi
  done
  if [[ -z "$EXPECT_PRESCAN" ]]; then
    b="$(get blocking-findings "$before")"; detail+=" prescan-blocking=${b:-?}"
    [[ "${b:-1}" == 0 ]] || { ok_seed=0; detail+="(EXPECTED 0)"; }
  fi
  if [[ -n "$EXPECT_IMAGE" ]]; then
    ib="$(image_blocking "$EXPECT_IMAGE")"
    if [[ "$ib" =~ ^[0-9]+$ && "$ib" -gt 0 ]]; then detail+=" image-${EXPECT_IMAGE}-blocking=${ib}"
    else ok_seed=0; detail+=" image-${EXPECT_IMAGE}-blocking=${ib}(EXPECTED>0)"; fi
  fi
  if [[ -n "$EXPECT_RUFF" ]]; then
    # capture first: with pipefail, `ruff ... | grep -q` reports ruff's exit code (1 = found something)
    codes="$(ruff_codes)"
    if grep -q "$EXPECT_RUFF" <<<"$codes"; then detail+=" ruff:${EXPECT_RUFF}"; else ok_seed=0; detail+=" ruff:${EXPECT_RUFF}(MISSING)"; fi
  fi

  labs/fix.sh "$ID" >/dev/null 2>&1 || { ok_seed=0; detail+=" fix-failed"; }
  after="$(prescan_outputs)"
  ab="$(get blocking-findings "$after")"
  if [[ "${ab:-1}" == 0 ]]; then detail+=" | after fix: prescan-blocking=0"
  else ok_seed=0; detail+=" | after fix: prescan-blocking=${ab:-?}(EXPECTED 0)"; fi
  if [[ -n "$EXPECT_IMAGE" ]]; then
    ia="$(image_blocking "$EXPECT_IMAGE")"
    if [[ "$ia" == 0 ]]; then detail+=" image-blocking=0"; else ok_seed=0; detail+=" image-blocking=${ia}(EXPECTED 0)"; fi
  fi
  if [[ -n "$EXPECT_RUFF" ]]; then
    codes="$(ruff_codes)"
    if grep -q "$EXPECT_RUFF" <<<"$codes"; then ok_seed=0; detail+=" ruff:${EXPECT_RUFF}(STILL THERE)"; else detail+=" ruff:clean"; fi
  fi

  cd "$REPO_ROOT" || exit 1
  if (( ok_seed )); then RESULTS+=("${C_G}✔${C_0} ${NAME}:${detail}"); else RESULTS+=("${C_R}✘${C_0} ${NAME}:${detail}"); FAILED=1; fi
  echo "${RESULTS[-1]}"
done

echo
echo "${C_B}Summary${C_0}"
printf '%s\n' "${RESULTS[@]}"
exit "$FAILED"
