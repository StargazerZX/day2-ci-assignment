# Sample data for local demos

`security-summary.json` is a **made-up** example of the file a pipeline produces with
(`scripts/security-report.py` → `security-summary.json`). The staging env file points the API at
it (`RELEASE_SECURITY_SUMMARY_FILE`), so the "Release security" card can be seen locally.
It validates against `api/contracts/security-summary.schema.json`.
