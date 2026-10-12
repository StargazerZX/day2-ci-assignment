# 02 · A secret "fixed" in the next commit

**Scenario:** an API key is hard-coded in `api/integrations.py`, and a second commit replaces it with
`os.environ.get(...)`. The current code is clean. The history is not.
**Caught by:** Gitleaks (it reads the history). Trivy, which scans only the current files, sees nothing.

```bash
labs/plant.sh 02
git log --oneline -2         # two commits: the key, then the "fix"
```

## What you should see

```text
| Gitleaks (history) | 1 | |
| TruffleHog (history) | 0 verified | 0 unverified |
| Trivy fs (CRITICAL,HIGH) | 0 (vuln 0, misconfig 0, secret 0) | ... |

Blocking findings:
  gitleaks    generic-api-key  api/integrations.py:2  commit b59464f
```

`git show <that commit>` shows the key, even though `cat api/integrations.py` doesn't.

## Things to notice

- This is why the prescan job checks out with `fetch-depth: 0` and why Gitleaks/TruffleHog scan `git`
  history, not just the directory. A scanner that looks only at the latest files says "clean" here.
- TruffleHog has no detector for a made-up "payment provider", so it can't flag this one. Gitleaks'
  *generic* rule (a key-looking name plus a high-entropy value) catches it. Different tools, different
  coverage: that's why the pipeline runs more than one.

## Fix it

Same as seed 01: **rotate** the key, then make the history not contain it. Here, squash the two commits into
one that never had the key (`git reset --soft HEAD~2 && git commit ...`), then `git push --force-with-lease`
if you had pushed.

<details><summary>Reference fix</summary>

`labs/fix.sh 02` squashes the two seed commits into one clean commit.
</details>

**Done?** `labs/reset.sh`
