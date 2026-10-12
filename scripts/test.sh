#!/usr/bin/env bash
# Run every unit test suite in the repo:
#   1. API (pytest) -- coverage >= 80%
#   2. scripts (security-report.py, against real scanner output)
#   3. frontend logic (node --test)
# The browser smoke test needs a running stack: local/up.sh dev && scripts/test-e2e.sh
#
#   scripts/test.sh                                # everything
#   scripts/test.sh --junitxml=reports/junit.xml   # extra args go to the API's pytest
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> API"
scripts/test-api.sh "$@"
echo "==> scripts (security-report.py)"
api/.venv/bin/python -m pytest -q -p no:cacheprovider -o addopts="" scripts/tests
echo "==> frontend (logic.js)"
node --test frontend/tests/logic.test.js
echo "==> all suites passed"
