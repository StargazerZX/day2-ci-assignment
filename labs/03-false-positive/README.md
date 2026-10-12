# 03 · A false positive, handled properly

**Scenario:** `local/sample/cache.ini` stores a content hash of a public file, to detect when it changes.
It is not a secret (anyone can recompute it), but it *looks* like one: a key-ish name and 40 random-looking characters.
**Caught by:** Gitleaks (`generic-api-key`).

```bash
labs/plant.sh 03
cat local/sample/cache.ini
```

## What you should see

```text
| Gitleaks (history) | 1 | |

Blocking findings:
  gitleaks    generic-api-key  local/sample/cache.ini:4  commit f9a1ec4
```

## Fix it: suppress *this finding*, with a reason

First **review** it: is it really not a secret? Here, `git hash-object local/sample/security-summary.json`
reproduces the value, so yes, it's a false positive. Then pick one of these:

1. **`.gitleaksignore`** at the repository root: one finding *fingerprint* per line
   (`<commit>:<file>:<rule>:<line>`, shown in the Gitleaks JSON report), with a comment saying who reviewed it and why.
2. **An inline `gitleaks:allow` comment** on the line itself. Simple, and it survives rebases, but it's easy to
   abuse in code review.

### The wrong fix

Tempting, and wrong: turning the rule off in a `.gitleaks.toml`:

```toml
[extend]
useDefault = true
disabledRules = ["generic-api-key"]
```

The pipeline goes green, and it also goes **blind**: that same rule is the only thing that catches seed 02's
leaked payment key. One noisy finding should cost one suppression, not a whole detector. Try it: disable the rule,
plant seed 02, and watch it slip through.

<details><summary>Reference fix</summary>

`labs/fix.sh 03` runs Gitleaks, takes the fingerprint of the finding in `local/sample/cache.ini`, and appends it to
`.gitleaksignore` under a dated justification comment. The CI's security summary then counts it as
**suppressed**, so accepted findings stay visible.

Note: a fingerprint contains the commit SHA. If you rebase or squash that commit, its fingerprint changes and the
finding comes back (option 2 doesn't have that problem).
</details>

**Done?** `labs/reset.sh`
