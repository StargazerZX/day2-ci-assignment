#!/usr/bin/env bash
# Seed 02: hard-code an API key, then "fix" it in the next commit. The tree is clean afterwards,
# but the key is still in the git history.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=labs/_lib.sh
source labs/_lib.sh
cat > api/integrations.py <<PY
"""Payment provider client (not wired in yet)."""
PAYMENT_API_KEY = "$(rand 'A-Za-z0-9' 32)"
PY
git add api/integrations.py
git commit -q -m "lab 02: add the payment provider integration"
cat > api/integrations.py <<'PY'
"""Payment provider client (not wired in yet)."""
import os

PAYMENT_API_KEY = os.environ.get("PAYMENT_API_KEY", "")
PY
git add api/integrations.py
git commit -q -m "lab 02: read the payment API key from the environment instead"
