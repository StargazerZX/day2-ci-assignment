"""Shared fixtures.

app.py reads its configuration from env vars at IMPORT time (12-factor style), so every test
that needs a different configuration re-imports the module with a fresh environment
(which also gives it a fresh, empty in-memory vote store).
"""
import importlib
import json
import pathlib
import sys

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

API_DIR = pathlib.Path(__file__).resolve().parents[1]
CONTRACTS = API_DIR / "contracts"
sys.path.insert(0, str(API_DIR))

# Every variable app.py reads -- cleared before each load so the developer's shell can't leak in.
APP_ENV_VARS = [
    "POD_NAME", "POD_NAMESPACE", "NODE_NAME", "APP_VERSION", "PODPOLL_ENV", "PLATFORM",
    "KUBERNETES_SERVICE_HOST", "ECS_CONTAINER_METADATA_URI_V4",
    "GIT_SHA", "GIT_REF", "BUILD_ID", "BUILD_URL", "CI_SYSTEM", "BUILD_TIME", "SOURCE_URL",
    "POLL_QUESTION", "POLL_OPTIONS", "CHAOS_READY_FAIL", "CHAOS_START_DELAY_SECONDS", "CHAOS_ERROR_RATE",
    "RESET_TOKEN", "RELEASE_SECURITY_SUMMARY", "RELEASE_SECURITY_SUMMARY_FILE",
]


@pytest.fixture
def load_app(monkeypatch):
    """load_app(**env) -> freshly imported app module (empty vote store)."""
    def _load(**env):
        for name in APP_ENV_VARS:
            monkeypatch.delenv(name, raising=False)
        for name, value in env.items():
            monkeypatch.setenv(name, str(value))
        sys.modules.pop("app", None)
        return importlib.import_module("app")
    yield _load
    sys.modules.pop("app", None)


@pytest.fixture
def api(load_app):
    mod = load_app()
    return mod, mod.app.test_client()


def _registry() -> Registry:
    resources = []
    for path in CONTRACTS.glob("*.schema.json"):
        doc = json.loads(path.read_text())
        resources.append((doc["$id"], Resource.from_contents(doc)))
    return Registry().with_resources(resources)


REGISTRY = _registry()


def assert_contract(name: str, payload) -> None:
    schema = json.loads((CONTRACTS / f"{name}.schema.json").read_text())
    errors = sorted(Draft202012Validator(schema, registry=REGISTRY).iter_errors(payload), key=str)
    assert not errors, f"{name} contract violated: " + "; ".join(e.message for e in errors)
