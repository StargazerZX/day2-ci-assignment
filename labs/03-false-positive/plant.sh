#!/usr/bin/env bash
# Seed 03: a content hash in a sample file. Not a secret at all, but it looks like one.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HASH="$(git hash-object local/sample/security-summary.json)"
cat > local/sample/cache.ini <<INI
# Content hash of security-summary.json: the UI reloads the sample when it changes.
# This is NOT a secret (anyone can recompute it with: git hash-object local/sample/security-summary.json).
[sample]
cache_key = ${HASH}
INI
git add local/sample/cache.ini
git commit -q -m "lab 03: cache key for the sample security summary"
