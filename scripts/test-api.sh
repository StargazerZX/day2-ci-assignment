#!/usr/bin/env bash
# Run the API test suite locally.
#
#   scripts/test-api.sh            # all API tests (coverage gate: 80% of app.py)
#   scripts/test-api.sh -k vote    # extra args go straight to pytest
#
# Needs Python 3.12 (python3.12 on PATH, or uv). CI sets PYTHON to the interpreter it installed.
set -euo pipefail
cd "$(dirname "$0")/../api"

VENV=.venv
if [[ ! -x "$VENV/bin/python" ]]; then
  if [[ -n "${PYTHON:-}" ]]; then "$PYTHON" -m venv "$VENV"
  elif command -v uv >/dev/null; then uv venv -q --python 3.12 "$VENV"
  else python3.12 -m venv "$VENV"; fi
fi
if command -v uv >/dev/null; then
  uv pip install -q --python "$VENV/bin/python" --require-hashes -r requirements.txt -r requirements-dev.txt
else
  "$VENV/bin/pip" install -q --require-hashes -r requirements.txt -r requirements-dev.txt
fi

"$VENV/bin/python" -m pytest "$@"
