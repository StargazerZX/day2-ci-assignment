#!/usr/bin/env bash
# labs/plant.sh NN -- plant lab seed NN on a new branch lab/NN-<name>, as a commit.
#
# A seed is a deliberate problem (a leaked fake key, a vulnerable dependency, a risky Dockerfile...)
# that the pipeline's scanners should catch. Then:
#   * push the branch and open a pull request in YOUR repository to watch CI flag it, and/or
#   * run labs/scan-local.sh to see the same scan on your machine.
# Read labs/NN-*/README.md for what to look for and how to fix it. Undo everything: labs/reset.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=labs/_lib.sh
source labs/_lib.sh
shopt -s nullglob

ID="${1:-}"
SEEDS=(labs/[0-9][0-9]-*/)
[[ "$ID" =~ ^[0-9]{2}$ ]] || die "usage: labs/plant.sh NN   (seeds: $(printf '%s ' "${SEEDS[@]}" | sed 's#labs/##g; s#/##g'))"
DIRS=(labs/"${ID}"-*/)
[[ ${#DIRS[@]} -eq 1 ]] || die "No lab seed ${ID}."
DIR="${DIRS[0]%/}"; NAME="${DIR#labs/}"
TITLE="$(head -1 "$DIR/README.md" | sed -E 's/^#+ *//')"
require_clean_tree
BASE="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BASE" == lab/* ]] && die "You are on a lab branch already. Run labs/reset.sh first."

git switch -q -c "lab/${NAME}"
printf '%s\n' "$BASE" > "$(git rev-parse --git-path labs-base)"
if [[ -x "$DIR/plant.sh" ]]; then
  "$DIR/plant.sh"                                   # seeds that generate fake secrets or several commits
else
  git apply --index "$DIR/seed.patch"
  git commit -q -m "lab ${ID}: ${TITLE}"
fi

echo
ok "Planted '${TITLE}' on branch lab/${NAME} (you came from '${BASE}')."
echo "  See it in CI:   git push -u origin lab/${NAME}   then open a pull request into main"
echo "  See it locally: labs/scan-local.sh$(grep -q '^EXPECT_IMAGE=..' "$DIR/expect" 2>/dev/null && printf ' --build %s' "$(sed -nE 's/^EXPECT_IMAGE="?([a-z-]+)"?/\1/p' "$DIR/expect")")"
echo "  Then read:      ${DIR}/README.md"
