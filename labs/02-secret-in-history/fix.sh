#!/usr/bin/env bash
# Reference fix for seed 02: rotate the key (can't be scripted for a fake one), then remove the
# commit that contained it. Here: squash the two lab commits into one that never had the key.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git reset -q --soft HEAD~2
git commit -q -m "lab 02: add the payment provider integration (key from the environment)"
echo "Squashed both commits into one: the hard-coded key is no longer in this branch's history."
echo "If you had pushed the branch: git push --force-with-lease"
