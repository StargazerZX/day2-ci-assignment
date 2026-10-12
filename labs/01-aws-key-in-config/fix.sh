#!/usr/bin/env bash
# Reference fix for seed 01. Step 1 (rotate the key in AWS) can't be scripted for a fake key.
# Step 2: the commit must disappear from history, not just the file from the tree. On a lab branch
# that nobody else has, that means rewriting the branch: drop the commit.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git reset -q --hard HEAD~1
echo "Dropped the commit that added deploy/aws/credentials (history rewritten)."
echo "If you had pushed the branch: git push --force-with-lease"
