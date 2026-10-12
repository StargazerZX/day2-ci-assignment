#!/usr/bin/env bash
# labs/reset.sh -- leave the current lab branch and delete it, back to where labs/plant.sh started.
# Anything on the lab branch is DISCARDED. If you pushed it, also delete it on GitHub:
#   git push origin --delete lab/NN-<name>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=labs/_lib.sh
source labs/_lib.sh
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == lab/* ]] || die "You are on '${BRANCH}', not a lab/* branch. Nothing to reset."
BASE_FILE="$(git rev-parse --git-path labs-base)"
BASE="$(cat "$BASE_FILE" 2>/dev/null || echo main)"
git switch -q --discard-changes "$BASE"
git branch -q -D "$BRANCH"
rm -f "$BASE_FILE"
ok "Back on '${BASE}'. '${BRANCH}' deleted locally."
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  warn "It still exists on GitHub: git push origin --delete ${BRANCH}"
fi
