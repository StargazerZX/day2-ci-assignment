# 08 · SQL injection (what these scanners *don't* catch)

**Scenario:** in the Postgres code path of `api/app.py`, someone replaces the parameterised `INSERT` with an
f-string ("simpler").
**Caught by:** none of Gitleaks, TruffleHog or Trivy. This is a **code** flaw, and that's the point of the seed.
A SAST tool catches it: SonarQube (coming next in the course), or locally right now, `ruff` with its
security rules (the Bandit set).

```bash
labs/plant.sh 08
git show
labs/scan-local.sh                                  # all green: exit 0
uvx ruff check api/      # or: pip install ruff && ruff check api/
```

## What you should see

The pipeline's scanners report nothing. Ruff (rules in `ruff.toml`) does:

```text
api/app.py:409:33: S608 Possible SQL injection vector through string-based query construction
```

## Things to notice

- Secret scanners and dependency/config scanners look at **what you ship and what you leak**. They don't read
  your logic. Catching this needs **static analysis of the code** (SAST).
- Here the value comes from a fixed list of options, so it's hard to exploit today. One refactor later, it isn't.
  Query parameters (`%s` plus a tuple) make the whole class of bug impossible.

## Fix it

Go back to `cur.execute("INSERT INTO votes (option, api_pod) VALUES (%s, %s)", (option, POD_NAME))`.

<details><summary>Reference fix</summary>

`labs/fix.sh 08` reverts the change.
</details>

**Done?** `labs/reset.sh`
