"""
PodPoll API  --  the "backend" tier.

A tiny Flask app that:
  * counts votes (in memory: restart the API and the votes are gone)
  * tells you WHICH instance and environment answered
  * tells you WHICH BUILD is running: version, git SHA, CI run   (so pipelines become visible)
  * shows the pipeline's security summary for this release, if the pipeline provides one

Everything environment-specific comes from environment variables (the Compose env files locally).
"""
import hmac
import json
import logging
import os
import random
import re
import socket
import threading
import time
from collections import Counter

from flask import Flask, jsonify, request

app = Flask(__name__)
log = logging.getLogger("podpoll")


# --- small env helpers --------------------------------------------------------
def env_bool(name: str) -> bool:
    return os.getenv(name, "").strip().lower() in ("1", "true", "yes", "on")


def env_float(name: str, default: float, lo: float, hi: float) -> float:
    try:
        return min(hi, max(lo, float(os.getenv(name, default))))
    except ValueError:
        return default


# --- build provenance (stamped into the image by CI as --build-arg -> ENV) ------
# Anything here can come from a branch name or a CI variable, so it is sanitised before it is
# shown anywhere. The frontend's stamp.sh applies the SAME rules at image build time.
def clean(value, allowed: str, default: str, max_len: int = 64) -> str:
    """Replace every character outside `allowed` (a regex character class body) with '-'."""
    value = (value or "").strip()
    if not value:
        return default
    return re.sub(f"[^{allowed}]", "-", value)[:max_len]


def clean_url(value) -> str:
    value = (value or "").strip()
    if re.fullmatch(r"https?://[0-9A-Za-z._~:/?#@!$&()*+,;=%-]+", value) and len(value) <= 512:
        return value
    return ""


def clean_sha(value) -> str:
    value = (value or "").strip().lower()
    return value if re.fullmatch(r"[0-9a-f]{7,40}", value) else "unknown"


def clean_time(value) -> str:
    value = (value or "").strip()
    return value if re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", value) else "unknown"


def build_info(env=os.environ) -> dict:
    sha = clean_sha(env.get("GIT_SHA"))
    source = clean_url(env.get("SOURCE_URL"))
    return {
        "version": clean(env.get("APP_VERSION"), "0-9A-Za-z.+-", "dev"),
        "git_sha": sha,
        "git_sha_short": sha[:7] if sha != "unknown" else "unknown",
        "git_ref": clean(env.get("GIT_REF"), "0-9A-Za-z._/+-", "unknown", 128),
        "build_id": clean(env.get("BUILD_ID"), "0-9A-Za-z._-", "local"),
        "build_url": clean_url(env.get("BUILD_URL")),
        "ci_system": clean(env.get("CI_SYSTEM"), "0-9a-z-", "local", 32),
        "build_time": clean_time(env.get("BUILD_TIME")),
        "source_url": source,
        "commit_url": f"{source}/commit/{sha}" if source and sha != "unknown" else "",
    }


BUILD = build_info()


# --- where am I running? kubernetes | ecs | docker ------------------------------
PLATFORMS = ("kubernetes", "ecs", "docker")


def detect_platform(env=os.environ) -> str:
    explicit = (env.get("PLATFORM") or "").strip().lower()
    if explicit in PLATFORMS:
        return explicit
    if env.get("KUBERNETES_SERVICE_HOST"):          # kubelet injects this into every pod
        return "kubernetes"
    if env.get("ECS_CONTAINER_METADATA_URI_V4"):    # the ECS agent injects this into every container
        return "ecs"
    return "docker"


PLATFORM = detect_platform()

# --- configuration (12-factor style: all from env vars) ---------------------
# NOTE on naming: never call a variable <SERVICE>_PORT. Kubernetes injects exactly such variables
# (e.g. API_PORT=tcp://10.96.x.x:5000 for a Service named "api"), and they would clash.
POD_NAME = os.getenv("POD_NAME") or socket.gethostname()     # instance identity (container hostname)
POD_NAMESPACE = os.getenv("POD_NAMESPACE", "unknown")
NODE_NAME = os.getenv("NODE_NAME", "unknown")
APP_VERSION = BUILD["version"]                                # baked into the image at build time
# The environment shown in the badge: dev | staging | prod | preview.
PODPOLL_ENV = os.getenv("PODPOLL_ENV") or POD_NAMESPACE

# --- chaos switches: all OFF by default. /healthz ignores every one of them. -----------------
CHAOS_READY_FAIL = env_bool("CHAOS_READY_FAIL")                         # /readyz -> 503
CHAOS_START_DELAY_SECONDS = env_float("CHAOS_START_DELAY_SECONDS", 0, 0, 600)
CHAOS_ERROR_RATE = env_float("CHAOS_ERROR_RATE", 0, 0, 1)               # share of votes -> 500

# Optional protection for POST /api/reset. Unset (the default) = open, an accepted risk for a demo.
RESET_TOKEN = os.getenv("RESET_TOKEN", "")


# --- the poll itself: configurable, so every workshop can ask its own question ---------------
DEFAULT_QUESTION = "Which pipeline gate saves you most often?"
DEFAULT_OPTIONS = ["Secret scan", "Unit tests", "SAST", "Dependency scan", "Image scan", "Code review"]


def parse_options(raw) -> list:
    """POLL_OPTIONS is comma-separated. Fewer than 2 usable options => fall back to the defaults."""
    seen = []
    for item in (raw or "").split(","):
        item = item.strip()[:40]
        if item and item not in seen:
            seen.append(item)
    return seen[:12] if len(seen) >= 2 else list(DEFAULT_OPTIONS)


POLL_QUESTION = (os.getenv("POLL_QUESTION") or DEFAULT_QUESTION).strip()[:200]
OPTIONS = parse_options(os.getenv("POLL_OPTIONS"))


# --- the vote store: in memory, on purpose ---------------------------------------------------
# No database: votes live in this process and vanish when it restarts. That's also why the API runs
# as ONE process (gunicorn.conf.py: 1 worker, several threads) and one container: two processes would
# each keep their own count. The lock makes concurrent votes from the threads safe.
class VoteStore:
    def __init__(self):
        self._lock = threading.Lock()
        self._counts = Counter()

    def add(self, option: str) -> None:
        with self._lock:
            self._counts[option] += 1

    def counts(self) -> dict:
        with self._lock:
            return dict(self._counts)

    def reset(self) -> None:
        with self._lock:
            self._counts.clear()


store = VoteStore()


def startup_delay() -> None:
    """CHAOS_START_DELAY_SECONDS: a slow-starting release. Called by gunicorn's on_starting hook
    (gunicorn.conf.py) BEFORE it binds the port, so health checks genuinely fail meanwhile."""
    if CHAOS_START_DELAY_SECONDS > 0:
        log.warning("chaos: delaying startup by %ss", CHAOS_START_DELAY_SECONDS)
        time.sleep(CHAOS_START_DELAY_SECONDS)


# --- health endpoints (Docker HEALTHCHECK, load balancer / orchestrator probes) ----
@app.get("/healthz")
def healthz():
    """Liveness: is the PROCESS alive? Ignores every chaos switch
    (otherwise a bad release would restart-loop instead of being rolled back)."""
    return "ok\n", 200


@app.get("/readyz")
def readyz():
    """Readiness: should this instance receive traffic? With CHAOS_READY_FAIL it says no,
    which is how a bad release looks to a load balancer or a deployment health check."""
    if CHAOS_READY_FAIL:
        return "chaos: CHAOS_READY_FAIL=true\n", 503
    return "ready\n", 200


# --- "who answered?" --------------------------------------------------------
@app.get("/api/info")
def info():
    return jsonify(
        pod=POD_NAME,
        namespace=POD_NAMESPACE,
        node=NODE_NAME,
        version=APP_VERSION,
        env=PODPOLL_ENV,
        platform=PLATFORM,
        git_sha=BUILD["git_sha"],
        ci_system=BUILD["ci_system"],
        reset_protected=bool(RESET_TOKEN),
        chaos={
            "ready_fail": CHAOS_READY_FAIL,
            "start_delay_seconds": CHAOS_START_DELAY_SECONDS,
            "error_rate": CHAOS_ERROR_RATE,
        },
    )


# --- "which build is this?" -------------------------------------------------
@app.get("/api/build")
def build():
    return jsonify(BUILD)


# --- "what did the pipeline find in this release?" ----------------------------
# The pipeline can pass its security summary to the running app, as compact JSON in
# RELEASE_SECURITY_SUMMARY or as a file (RELEASE_SECURITY_SUMMARY_FILE).
# No data => {"available": false} and the UI hides the card.
def release_security() -> dict:
    raw = os.getenv("RELEASE_SECURITY_SUMMARY", "")
    path = os.getenv("RELEASE_SECURITY_SUMMARY_FILE", "")
    if not raw and path:
        try:
            with open(path) as f:
                raw = f.read()
        except OSError:
            raw = ""
    if not raw.strip():
        return {"available": False}
    try:
        summary = json.loads(raw)
    except ValueError:
        return {"available": False, "error": "release security summary is not valid JSON"}
    if not isinstance(summary, dict):
        return {"available": False, "error": "release security summary must be a JSON object"}
    return {"available": True, "summary": summary}


@app.get("/api/release/security")
def release_security_endpoint():
    return jsonify(release_security())


# --- the poll ---------------------------------------------------------------
@app.get("/api/results")
def results():
    counts = store.counts()
    rows = [{"option": o, "votes": int(counts.get(o, 0))} for o in OPTIONS]
    return jsonify(
        results=rows,
        total=sum(x["votes"] for x in rows),
        served_by=POD_NAME,
        question=POLL_QUESTION,
    )


@app.post("/api/vote")
def vote():
    body = request.get_json(silent=True) or {}
    option = body.get("option")
    if option not in OPTIONS:
        return jsonify(error=f"option must be one of {OPTIONS}"), 400
    if CHAOS_ERROR_RATE and random.random() < CHAOS_ERROR_RATE:  # noqa: S311 -- not crypto
        return jsonify(error="chaos: injected failure (CHAOS_ERROR_RATE)"), 500
    store.add(option)
    return jsonify(ok=True, option=option, served_by=POD_NAME)


@app.post("/api/reset")
def reset():
    if RESET_TOKEN:
        supplied = request.headers.get("X-Reset-Token", "")
        # compare_digest: constant-time, so the token can't be guessed byte by byte from timings
        if not hmac.compare_digest(supplied.encode(), RESET_TOKEN.encode()):
            return jsonify(error="reset requires a valid X-Reset-Token header"), 403
    store.reset()
    return jsonify(ok=True)


if __name__ == "__main__":  # local dev only; in the container we use gunicorn
    startup_delay()
    app.run(host="0.0.0.0", port=5000)  # noqa: S104
