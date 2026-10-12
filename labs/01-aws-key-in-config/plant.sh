#!/usr/bin/env bash
# Seed 01: commit an AWS credentials file. The key is random and FAKE (it can't access anything),
# but it has exactly the shape of a real one.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=labs/_lib.sh
source labs/_lib.sh
mkdir -p deploy/aws
cat > deploy/aws/credentials <<CREDS
# Credentials for the deploy script. TODO: remove before merging!
[default]
aws_access_key_id = AKIA$(rand 'A-Z2-7' 16)
aws_secret_access_key = $(rand 'A-Za-z0-9/+' 40)
region = eu-central-1
CREDS
git add deploy/aws/credentials
git commit -q -m "lab 01: add AWS credentials for the deploy script"
