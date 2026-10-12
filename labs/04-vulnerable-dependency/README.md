# 04 · A dependency with a known vulnerability

**Scenario:** while debugging, someone pins Flask 3.0.3 and Werkzeug 3.0.1 "temporarily", and regenerates the
hashed lock file. The app works and every test passes.
**Caught by:** Trivy (filesystem scan of `api/requirements.txt`).

```bash
labs/plant.sh 04
git show --stat
```

## What you should see

```text
| Trivy fs (CRITICAL,HIGH) | 1 (vuln 1, misconfig 0, secret 0) | 0 without a fix yet, 7 at lower severity, ... |

Blocking findings:
  trivy       HIGH CVE-2024-34069  werkzeug 3.0.1 -> 3.0.3  (api/requirements.txt)
```

Open `trivy-report-prescan.json` (CI artifact `prescan-reports`, or `reports/local/`) and read the advisory:
what is vulnerable, under which conditions, and which version fixes it.

## Things to notice

- **Tests passing ≠ safe.** Nothing functional broke; the risk is invisible without a scanner.
- The gate blocks **fixable** HIGH/CRITICAL findings only. The "7 at lower severity" (MEDIUM/LOW) are
  reported, not blocking. Ask yourselves whether that threshold is right for your team.

## Fix it (two legitimate options)

1. **Upgrade** (preferred): remove the pins from `api/requirements.in` and regenerate the lock:

   ```bash
   cd api && uv pip compile --universal --python-version 3.12 --generate-hashes requirements.in -o requirements.txt
   ```

2. **Accept the risk, explicitly and temporarily**, when you can't upgrade yet (e.g. waiting for a vendor).
   A `.trivyignore.yaml` at the repository root, with a reason and an **expiry date**:

   ```yaml
   vulnerabilities:
     - id: CVE-2024-34069
       statement: "Debugger is never enabled in production. Upgrade tracked in issue #12."
       expired_at: 2026-12-31
   ```

   The scan then lists it as **suppressed** (still visible in the summary), and after the expiry date it
   blocks again, so "temporarily" can't quietly become "forever".

<details><summary>Reference fix</summary>

`labs/fix.sh 04` reverts the pinning commit (back to the current Flask/Werkzeug).
</details>

**Done?** `labs/reset.sh`
