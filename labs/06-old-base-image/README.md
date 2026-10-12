# 06 · An outdated base image

**Scenario:** the frontend's base image is "downgraded" to a version from 2024 (say, copied from an old
tutorial). The Dockerfile is otherwise perfect, and the app works.
**Caught by:** the **postscan** job (Trivy on the *built image*). The prescan job stays green.

```bash
labs/plant.sh 06
git show
labs/scan-local.sh --build frontend      # builds the image locally, then scans it like CI does
```

## What you should see

The prescan is clean. The image scan fails (in CI: the `build (frontend)` job, at **Postscan Security Checks**,
and the image is **never pushed**):

```text
| 6 (vuln 6, misconfig 0, secret 0) | 0 without a fix yet, 16 at lower severity, 0 suppressed |

Blocking findings (first 40):
  HIGH CVE-2024-6119  libcrypto3 3.1.6-r2 -> 3.1.7-r0  (... (alpine 3.19.3))
  HIGH CVE-2024-6119  libssl3 3.1.6-r2 -> 3.1.7-r0  (... (alpine 3.19.3))
  HIGH CVE-2025-26519  musl 1.2.4_git20230717-r4 -> 1.2.4_git20230717-r5  (... (alpine 3.19.3))
  HIGH CVE-2025-26519  musl-utils ...
  HIGH CVE-2026-40200  musl ...
  HIGH CVE-2026-40200  musl-utils ...
```

## Things to notice

- **Why scan images, not just files:** the vulnerable packages (OpenSSL, musl) come from the base image's
  operating system. They appear in no file of this repository, so the filesystem scan can't see them.
- The pipeline scans **before pushing**: a vulnerable image never reaches the registry.
- The base is pinned by **digest** (`@sha256:...`). That makes builds reproducible, and it also means nothing
  updates by itself. Something has to bump it on purpose (Dependabot's `docker` ecosystem can).

## Fix it

Move to a current base image, pinned by digest. To find one:
`docker buildx imagetools inspect nginxinc/nginx-unprivileged:<current-version>-alpine-slim`.

<details><summary>Reference fix</summary>

`labs/fix.sh 06` reverts to the repository's current base image (nginx 1.30.5, alpine-slim).
</details>

**Done?** `labs/reset.sh`
