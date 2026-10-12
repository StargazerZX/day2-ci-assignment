"""Endpoint tests. Shapes are checked against api/contracts/."""
import json
import threading

import pytest

from conftest import assert_contract


# --- health ------------------------------------------------------------------
def test_healthz_is_always_ok(api):
    _, client = api
    res = client.get("/healthz")
    assert res.status_code == 200 and res.text == "ok\n"


def test_readyz_is_ready_by_default(api):
    _, client = api
    res = client.get("/readyz")
    assert res.status_code == 200 and res.text == "ready\n"


# --- info --------------------------------------------------------------------
def test_info(load_app):
    mod = load_app(POD_NAME="api-1", POD_NAMESPACE="dev", NODE_NAME="node-a", APP_VERSION="2.0",
                   GIT_SHA="0123456789abcdef0123456789abcdef01234567", CI_SYSTEM="github-actions")
    d = mod.app.test_client().get("/api/info").get_json()
    assert_contract("info", d)
    assert d["pod"] == "api-1" and d["namespace"] == "dev" and d["node"] == "node-a"
    assert d["version"] == "2.0" and d["env"] == "dev"           # env falls back to the namespace
    assert d["git_sha"].startswith("0123456") and d["ci_system"] == "github-actions"
    assert d["platform"] == "docker" and d["reset_protected"] is False
    assert d["chaos"] == {"ready_fail": False, "start_delay_seconds": 0, "error_rate": 0}


def test_podpoll_env_wins_over_namespace(load_app):
    d = load_app(POD_NAMESPACE="team-a", PODPOLL_ENV="staging").app.test_client().get("/api/info").get_json()
    assert d["env"] == "staging" and d["namespace"] == "team-a"


def test_info_defaults(load_app):
    d = load_app().app.test_client().get("/api/info").get_json()
    assert d["namespace"] == "unknown" and d["env"] == "unknown" and d["node"] == "unknown"
    assert d["version"] == "dev" and d["pod"]                     # pod = container hostname


@pytest.mark.parametrize("env,expected", [
    ({}, "docker"),
    ({"KUBERNETES_SERVICE_HOST": "10.96.0.1"}, "kubernetes"),
    ({"ECS_CONTAINER_METADATA_URI_V4": "http://169.254.170.2/v4/abc"}, "ecs"),
    ({"PLATFORM": "ECS", "KUBERNETES_SERVICE_HOST": "10.96.0.1"}, "ecs"),   # explicit wins
    ({"PLATFORM": "bogus"}, "docker"),                                       # invalid -> auto
])
def test_detect_platform(load_app, env, expected):
    assert load_app().detect_platform(env) == expected


# --- build provenance --------------------------------------------------------
def test_build_defaults(api):
    _, client = api
    d = client.get("/api/build").get_json()
    assert_contract("build", d)
    assert d == {"version": "dev", "git_sha": "unknown", "git_sha_short": "unknown", "git_ref": "unknown",
                 "build_id": "local", "build_url": "", "ci_system": "local", "build_time": "unknown",
                 "source_url": "", "commit_url": ""}


def test_build_from_ci(load_app):
    sha = "abcdef0123456789abcdef0123456789abcdef01"
    mod = load_app(APP_VERSION="1.4.0", GIT_SHA=sha.upper(), GIT_REF="refs/heads/main", BUILD_ID="42",
                   BUILD_URL="https://github.com/u/podpoll/actions/runs/42", CI_SYSTEM="github-actions",
                   BUILD_TIME="2026-10-11T09:30:00Z", SOURCE_URL="https://github.com/u/podpoll")
    d = mod.app.test_client().get("/api/build").get_json()
    assert_contract("build", d)
    assert d["git_sha"] == sha and d["git_sha_short"] == "abcdef0"
    assert d["commit_url"] == f"https://github.com/u/podpoll/commit/{sha}"
    assert d["build_time"] == "2026-10-11T09:30:00Z" and d["build_id"] == "42"


@pytest.mark.parametrize("raw,expected", [
    ("2.3.1-abc123", "2.3.1-abc123"),
    ("feature/login", "feature-login"),          # a branch name with "/" would break sed in the frontend build
    ("1.0 ; rm -rf /", "1.0---rm--rf--"),
    ("v1.2.3+build.7", "v1.2.3+build.7"),
    ("", "dev"),
])
def test_app_version_is_sanitised(load_app, raw, expected):
    assert load_app(APP_VERSION=raw).APP_VERSION == expected


def test_untrusted_build_values_are_dropped(load_app):
    mod = load_app(GIT_SHA="not-a-sha", BUILD_URL='https://x/"><script>', SOURCE_URL="javascript:alert(1)",
                   BUILD_TIME="yesterday", BUILD_ID="12 34", CI_SYSTEM="Jenkins!")
    d = mod.BUILD
    assert d["git_sha"] == "unknown" and d["build_url"] == "" and d["source_url"] == ""
    assert d["build_time"] == "unknown" and d["build_id"] == "12-34" and d["ci_system"] == "-enkins-"
    assert d["commit_url"] == ""


# --- poll --------------------------------------------------------------------
def test_results_zero_filled_with_default_question(api):
    _, client = api
    d = client.get("/api/results").get_json()
    assert_contract("results", d)
    assert [x["option"] for x in d["results"]] == ["Secret scan", "Unit tests", "SAST",
                                                  "Dependency scan", "Image scan", "Code review"]
    assert d["total"] == 0 and d["question"] == "Which pipeline gate saves you most often?"


def test_vote_and_count(api):
    _, client = api
    for _ in range(3):
        res = client.post("/api/vote", json={"option": "SAST"})
        assert res.status_code == 200
        assert_contract("vote", res.get_json())
    client.post("/api/vote", json={"option": "Image scan"})
    d = client.get("/api/results").get_json()
    counts = {x["option"]: x["votes"] for x in d["results"]}
    assert counts["SAST"] == 3 and counts["Image scan"] == 1 and d["total"] == 4


def test_concurrent_votes_are_all_counted(api):
    """gunicorn runs several threads in one process: no vote may be lost."""
    mod, _ = api
    threads = [threading.Thread(target=lambda: [mod.store.add("SAST") for _ in range(500)]) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert mod.store.counts()["SAST"] == 4000


@pytest.mark.parametrize("body", [{"option": "Pod"}, {}, None, {"option": 1}])
def test_vote_rejects_unknown_option(api, body):
    _, client = api
    res = client.post("/api/vote", json=body) if body is not None else client.post("/api/vote", data="x")
    assert res.status_code == 400
    assert_contract("error", res.get_json())


def test_custom_poll(load_app):
    mod = load_app(POLL_QUESTION="Tabs or spaces?", POLL_OPTIONS=" Tabs , Spaces,,Tabs ")
    client = mod.app.test_client()
    d = client.get("/api/results").get_json()
    assert d["question"] == "Tabs or spaces?" and [x["option"] for x in d["results"]] == ["Tabs", "Spaces"]
    assert client.post("/api/vote", json={"option": "SAST"}).status_code == 400


@pytest.mark.parametrize("raw", ["", "only-one", " , ,"])
def test_too_few_options_fall_back_to_defaults(load_app, raw):
    mod = load_app()
    assert mod.parse_options(raw) == mod.DEFAULT_OPTIONS


def test_options_are_capped(load_app):
    mod = load_app()
    opts = mod.parse_options(",".join(f"o{i}" for i in range(20)) + "," + "x" * 99)
    assert len(opts) == 12 and all(len(o) <= 40 for o in opts)


# --- reset -------------------------------------------------------------------
def test_reset_is_open_by_default(api):
    _, client = api
    client.post("/api/vote", json={"option": "SAST"})
    assert client.post("/api/reset").get_json() == {"ok": True}
    assert client.get("/api/results").get_json()["total"] == 0


def test_reset_token(load_app):
    mod = load_app(RESET_TOKEN="s3cr3t-for-tests")
    client = mod.app.test_client()
    client.post("/api/vote", json={"option": "SAST"})
    assert client.get("/api/info").get_json()["reset_protected"] is True
    assert client.post("/api/reset").status_code == 403
    assert client.post("/api/reset", headers={"X-Reset-Token": "wrong"}).status_code == 403
    assert client.get("/api/results").get_json()["total"] == 1
    res = client.post("/api/reset", headers={"X-Reset-Token": "s3cr3t-for-tests"})
    assert res.status_code == 200 and client.get("/api/results").get_json()["total"] == 0


# --- chaos -------------------------------------------------------------------
def test_chaos_ready_fail(load_app):
    client = load_app(CHAOS_READY_FAIL="true").app.test_client()
    res = client.get("/readyz")
    assert res.status_code == 503 and "CHAOS_READY_FAIL" in res.text
    assert client.get("/healthz").status_code == 200       # liveness ignores chaos
    assert client.get("/api/info").get_json()["chaos"]["ready_fail"] is True


def test_chaos_error_rate(load_app):
    client = load_app(CHAOS_ERROR_RATE="1").app.test_client()
    res = client.post("/api/vote", json={"option": "SAST"})
    assert res.status_code == 500 and "chaos" in res.get_json()["error"]
    assert client.post("/api/vote", json={"option": "nope"}).status_code == 400   # validation first
    assert client.get("/healthz").status_code == 200


def test_chaos_error_rate_partial(load_app, monkeypatch):
    mod = load_app(CHAOS_ERROR_RATE="0.2")
    client = mod.app.test_client()
    monkeypatch.setattr(mod.random, "random", lambda: 0.5)
    assert client.post("/api/vote", json={"option": "SAST"}).status_code == 200
    monkeypatch.setattr(mod.random, "random", lambda: 0.1)
    assert client.post("/api/vote", json={"option": "SAST"}).status_code == 500


@pytest.mark.parametrize("raw,expected", [("0.2", 0.2), ("5", 1.0), ("-1", 0.0), ("lots", 0.0)])
def test_chaos_error_rate_is_clamped(load_app, raw, expected):
    assert load_app(CHAOS_ERROR_RATE=raw).CHAOS_ERROR_RATE == expected


def test_chaos_start_delay(load_app, monkeypatch):
    mod = load_app(CHAOS_START_DELAY_SECONDS="12")
    slept = []
    monkeypatch.setattr(mod.time, "sleep", slept.append)
    mod.startup_delay()
    assert slept == [12.0]


def test_no_start_delay_by_default(load_app, monkeypatch):
    mod = load_app()
    monkeypatch.setattr(mod.time, "sleep", lambda s: pytest.fail("should not sleep"))
    mod.startup_delay()


# --- release security --------------------------------------------------------
SUMMARY = {
    "schema_version": 1, "generated_at": "2026-10-11T10:00:00Z", "git_sha": "abc1234", "version": "1.4.0",
    "status": "pass", "gate": "CRITICAL,HIGH (fixable)",
    "totals": {"critical": 0, "high": 0, "medium": 2, "low": 5, "unknown": 0, "suppressed": 1},
    "tools": [{"name": "trivy-image", "category": "image", "status": "pass",
               "findings": {"critical": 0, "high": 0, "medium": 2, "low": 5, "unknown": 0}, "suppressed": 1}],
}


def test_release_security_absent(api):
    _, client = api
    d = client.get("/api/release/security").get_json()
    assert_contract("release-security", d)
    assert d == {"available": False}


def test_release_security_from_env(load_app):
    client = load_app(RELEASE_SECURITY_SUMMARY=json.dumps(SUMMARY)).app.test_client()
    d = client.get("/api/release/security").get_json()
    assert_contract("release-security", d)
    assert d["available"] is True and d["summary"]["totals"]["suppressed"] == 1


def test_release_security_from_file(load_app, tmp_path):
    f = tmp_path / "summary.json"
    f.write_text(json.dumps(SUMMARY))
    client = load_app(RELEASE_SECURITY_SUMMARY_FILE=str(f)).app.test_client()
    assert client.get("/api/release/security").get_json()["available"] is True


@pytest.mark.parametrize("env", [
    {"RELEASE_SECURITY_SUMMARY": "{not json"},
    {"RELEASE_SECURITY_SUMMARY": "[1, 2]"},
    {"RELEASE_SECURITY_SUMMARY_FILE": "/does/not/exist.json"},
])
def test_release_security_bad_input_is_hidden(load_app, env):
    d = load_app(**env).app.test_client().get("/api/release/security").get_json()
    assert d["available"] is False
