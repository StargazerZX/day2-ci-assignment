#!/usr/bin/env bash
# labs/fix.sh NN -- apply the REFERENCE fix for seed NN on its lab branch (try your own first!).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=labs/_lib.sh
source labs/_lib.sh
shopt -s nullglob
ID="${1:-}"; [[ "$ID" =~ ^[0-9]{2}$ ]] || die "usage: labs/fix.sh NN"
DIRS=(labs/"${ID}"-*/); [[ ${#DIRS[@]} -eq 1 ]] || die "No lab seed ${ID}."
DIR="${DIRS[0]%/}"; NAME="${DIR#labs/}"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "lab/${NAME}" ]] || die "Switch to lab/${NAME} first (labs/plant.sh ${ID})."
require_clean_tree
if [[ -x "$DIR/fix.sh" ]]; then
  "$DIR/fix.sh"
else
  git revert --no-edit HEAD >/dev/null
  echo "Reverted the seed commit."
fi
ok "Reference fix applied. Re-scan: labs/scan-local.sh   (or push the branch again)"
