# Security labs: make the pipeline catch something

Each lab **plants a deliberate problem** in PodPoll on its own branch. You then watch the pipeline's
scanners flag it, understand *why*, and fix it properly.

| # | Seed | Caught by | Lesson |
|---|---|---|---|
| [01](01-aws-key-in-config/) | AWS key committed in a config file | Gitleaks, Trivy (CRITICAL); TruffleHog *unverified* | rotate first; verified vs. unverified |
| [02](02-secret-in-history/) | Secret "fixed" in the next commit | Gitleaks only (history) | why secret scanners read the history |
| [03](03-false-positive/) | A content hash that looks like a key | Gitleaks | suppress one finding with a reason, never a whole rule |
| [04](04-vulnerable-dependency/) | Werkzeug 3.0.1 pinned "temporarily" | Trivy fs (CVE-2024-34069, HIGH) | upgrade, or accept the risk with an expiry date |
| [05](05-dockerfile-root/) | Dockerfile runs as root, sloppy `apt-get` | Trivy misconfig (DS-0002, DS-0029) | catch it before building anything |
| [06](06-old-base-image/) | Outdated base image | **postscan** only (6 × HIGH, OpenSSL/musl) | why images are scanned, not just files |
| [07](07-command-injection/) | A "debug" endpoint that runs a shell command | **none of the three** (ruff S602 / SonarQube) | what these tools *can't* see: SAST |

All seeds are generated or applied on your machine. **Nothing in this repository is a real or reusable
secret.** The fake keys are created randomly when you plant a seed.

## How to do a lab

```bash
labs/plant.sh 04                    # creates branch lab/04-vulnerable-dependency with the seed committed
```

Then watch it get caught, either way:

- **In CI (your own repository):** `git push -u origin lab/04-vulnerable-dependency`, then open a pull request
  into `main`. The run turns red; open the job's **summary** for the table and the blocking findings, and the
  `prescan-reports` / `postscan-*` artifacts for the full JSON reports.
- **Locally:** `labs/scan-local.sh` (seed 06: `labs/scan-local.sh --build frontend`). It runs the same
  script as CI, with the same tool versions, and exits 1 on blocking findings.

Read the seed's README, fix it yourself (on the lab branch), and scan again. Stuck? `labs/fix.sh NN` applies the
reference fix. Finished: `labs/reset.sh` returns you to where you started and deletes the lab branch
(plus `git push origin --delete lab/...` if you pushed it).

## What "blocking" means here

The pipeline (`.github/workflows/ci.yml`) turns **red** on:

- any **Gitleaks** finding
- a **verified** TruffleHog secret (it checked with the provider that the credential works)
- a **fixable** Trivy finding (vulnerability, misconfiguration or secret) at **CRITICAL or HIGH**

Everything else (unverified secrets, vulnerabilities without a fix yet, MEDIUM/LOW) is **reported** in the
summary but doesn't fail the run. Accepted risks (`.gitleaksignore`, `.trivyignore.yaml`) show up as
*suppressed*, so they stay visible.

To run the pipeline report-only (never red), start it manually from the Actions tab with **fail-on-findings**
unticked.

## Requirements for running locally

`git`, `jq`, `curl`, Docker (for seed 06 and building images), Linux or macOS (on Windows use WSL).
`labs/scan-local.sh` downloads Gitleaks, TruffleHog and Trivy into `.labs-tools/` the first time, at
the versions pinned in `.github/prescan/action.yml`, after verifying their release checksums.

## For whoever maintains this repo

`labs/verify-all.sh` plants every seed in a throwaway clone, checks that the expected tool flags it, applies
the reference fix and checks that nothing blocks anymore. Run it after changing the scanners, their
versions, or the app.
