# 01 · An AWS key committed in a config file

**Scenario:** someone adds `deploy/aws/credentials` "just for the deploy script" with a TODO to remove it.
**Caught by:** Gitleaks (history), Trivy (secret scanner, CRITICAL). TruffleHog reports it as *unverified*.

```bash
labs/plant.sh 01
```

The key is generated randomly when you plant the seed: it has the exact shape of an AWS key but grants
access to nothing. (Nothing in this repository is a real or reusable secret.)

## What you should see

`labs/scan-local.sh` (exit code 1), and the same table in the **prescan** job summary in CI:

```text
| Gitleaks (history) | 2 | |
| TruffleHog (history) | 0 verified | 1 unverified |
| Trivy fs (CRITICAL,HIGH) | 2 (vuln 0, misconfig 0, secret 2) | ... |

Blocking findings:
  gitleaks    generic-api-key  deploy/aws/credentials:4  commit ac61900
  gitleaks    aws-access-token  deploy/aws/credentials:3  commit ac61900
  trivy       CRITICAL secret aws-access-key-id  deploy/aws/credentials:3
  trivy       CRITICAL secret aws-secret-access-key  deploy/aws/credentials:4
```

**GitHub may stop you before CI does.** Pushing an AWS key to a public repository can be blocked by GitHub's
*secret scanning push protection*. That's another layer of the same defence. To let CI see the seed anyway,
follow the link in the push error and mark it as a false positive / used in tests (it really is fake).

## Things to notice

- **Three tools, three opinions.** Gitleaks matches patterns. Trivy's secret scanner rates it CRITICAL.
  TruffleHog actually **asks AWS** whether the key works: it doesn't, so it is *unverified*, and the pipeline
  reports it without blocking on it. A *verified* secret would block, because it means someone can use it right now.
- Gitleaks and TruffleHog scan the **git history**, Trivy scans the **files**. Seed 02 shows why both matter.

## Fix it

Deleting the file in a new commit is **not** a fix: the key stays in the history, and anyone can read it there.

1. **Rotate first.** For a real key: deactivate it in AWS IAM now and check CloudTrail for its use. Assume it
   was copied the moment it was pushed (bots scrape public GitHub within minutes).
2. **Remove it from history.** On your own unshared branch: drop or rewrite the commit, then
   `git push --force-with-lease`. On a shared branch you'd need `git filter-repo` and to tell everyone. That's
   painful, and it's why rotation (step 1) comes first.
3. **Prevent it:** credentials come from the environment or a secret store, never from a file in the repo
   (in GitHub Actions: repository secrets or OIDC).

<details><summary>Reference fix</summary>

`labs/fix.sh 01` drops the seed commit (`git reset --hard HEAD~1`), then scan again: all zeros.
</details>

**Done?** `labs/reset.sh` (and `git push origin --delete lab/01-aws-key-in-config` if you pushed it).
