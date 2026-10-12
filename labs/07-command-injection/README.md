# 07 · Command injection (what these scanners *don't* catch)

**Scenario:** to help debug networking, someone adds a "troubleshooting" endpoint to `api/app.py`:
`GET /api/diag/ping?host=example.com` runs `ping` through a shell, with the `host` parameter pasted straight
into the command.
**Caught by:** none of Gitleaks, TruffleHog or Trivy. This is a **code** flaw, and that's the point of this lab.
A SAST tool catches it: SonarQube (coming next in the course), or locally right now, `ruff` with its
security rules (the Bandit set).

```bash
labs/plant.sh 07
git show
labs/scan-local.sh                                  # all green: exit 0
uvx ruff check api/      # or: pip install ruff && ruff check api/
```

## What you should see

The pipeline's scanners report nothing. Ruff (rules in `ruff.toml`) does:

```text
api/app.py:292:11: S602 `subprocess` call with `shell=True` identified, security issue
```

## See why it matters

Run the seeded app (`local/up.sh dev`) and ask the endpoint to ping a "host" that is really a second command:

```bash
curl -s 'http://localhost:8081/api/diag/ping?host=localhost;id' | jq -r .output
```

`id` runs inside the API container. Anything else would too: reading files, environment variables
(credentials!), or calling out to the internet. The container's hardening (non-root user, read-only filesystem,
no capabilities) limits the damage, but doesn't make it acceptable.

## Things to notice

- Secret scanners and dependency/config scanners look at **what you ship and what you leak**. They don't read
  your logic. Catching this needs **static analysis of the code** (SAST).
- The fix is not to filter characters out of `host`. Never build a shell command from user input: pass an
  argument list (`subprocess.run(["ping", "-c", "1", host])`, no shell), validate the input against what it
  should be (a hostname), or don't ship a debug endpoint at all.

## Fix it

Remove the endpoint, or rewrite it without a shell and with input validation.

<details><summary>Reference fix</summary>

`labs/fix.sh 07` reverts the change (removes the endpoint).
</details>

**Done?** `labs/reset.sh`
