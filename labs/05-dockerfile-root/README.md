# 05 · A Dockerfile that runs as root

**Scenario:** to "quickly add curl for debugging", someone adds `apt-get install curl` to `api/Dockerfile` and
removes the `USER 10001:10001` line because a permission error got in the way.
**Caught by:** Trivy (misconfiguration scanner on the Dockerfile), in the **prescan** job, before anything is built.

```bash
labs/plant.sh 05
git show
```

## What you should see

```text
| Trivy fs (CRITICAL,HIGH) | 2 (vuln 0, misconfig 2, secret 0) | ... |

Blocking findings:
  trivy       HIGH DS-0002  Image user should not be 'root'  (api/Dockerfile)
  trivy       HIGH DS-0029  'apt-get' missing '--no-install-recommends'  (api/Dockerfile)
```

## Things to notice

- A container running as root turns any remote-code-execution bug in the app into root inside the container,
  one step from the host. A non-root `USER` costs nothing.
- `--no-install-recommends` (and cleaning the apt lists) keeps extra packages, and their CVEs, out of the image.
- Misconfiguration scanning works on **files**: no image build needed, so it fails fast.

## Fix it

Put the `USER` back. If you really need a debugging tool, use a separate debug image or
`docker run --rm -it --user 0 <image> sh`, or `kubectl debug`, never the production image.

<details><summary>Reference fix</summary>

`labs/fix.sh 05` reverts the change.
</details>

**Done?** `labs/reset.sh`
