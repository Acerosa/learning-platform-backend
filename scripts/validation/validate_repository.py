#!/usr/bin/env python3
"""Dependency-free structural and manifest validation for this repository."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIGRATION_PATTERN = re.compile(r"^(\d{14})_[a-z0-9_]+\.sql$")
SEMVER_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
STABLE_KEY_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

REQUIRED_PATHS = (
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "supabase/config.toml",
    "supabase/migrations",
    "supabase/seed.sql",
    "supabase/tests/database",
    "supabase/tests/rls",
    "supabase/tests/api",
    "supabase/tests/integration",
    "supabase/data/manifests",
    "docs/architecture.md",
    "docs/database.md",
    "docs/api.md",
    "docs/rls.md",
    "docs/migrations.md",
    "docs/admin-api.md",
    "docs/release-process.md",
)


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)


def validate_paths(failures: list[str]) -> None:
    for relative in REQUIRED_PATHS:
        if not (ROOT / relative).exists():
            fail(f"missing required path: {relative}", failures)


def validate_migrations(failures: list[str]) -> None:
    migration_dir = ROOT / "supabase" / "migrations"
    names = sorted(path.name for path in migration_dir.glob("*.sql"))
    timestamps: list[str] = []
    for name in names:
        match = MIGRATION_PATTERN.fullmatch(name)
        if not match:
            fail(f"invalid migration filename: {name}", failures)
            continue
        timestamps.append(match.group(1))
    duplicates = sorted({value for value in timestamps if timestamps.count(value) > 1})
    if duplicates:
        fail(f"duplicate migration timestamps: {', '.join(duplicates)}", failures)


def load_json(path: Path, failures: list[str]):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"invalid JSON {path.relative_to(ROOT)}: {error}", failures)
        return None


def validate_hub_registry(failures: list[str]) -> None:
    path = ROOT / "supabase" / "data" / "manifests" / "hub-registry.json"
    data = load_json(path, failures)
    if not isinstance(data, dict):
        return
    hubs = data.get("hubs")
    if not isinstance(hubs, list) or not hubs:
        fail("hub-registry.json must contain at least one hub", failures)
        return
    required = {
        "hubCode",
        "hubName",
        "hubVersion",
        "platformVersion",
        "subject",
        "repository",
        "deploymentUrl",
        "curriculumModel",
        "activityTypes",
        "features",
        "status",
        "active",
    }
    seen: set[str] = set()
    for index, hub in enumerate(hubs):
        if not isinstance(hub, dict):
            fail(f"hub registry item {index} is not an object", failures)
            continue
        missing = sorted(required - hub.keys())
        if missing:
            fail(f"hub registry item {index} is missing: {', '.join(missing)}", failures)
        code = hub.get("hubCode")
        if not isinstance(code, str) or not STABLE_KEY_PATTERN.fullmatch(code):
            fail(f"invalid hubCode at item {index}: {code!r}", failures)
        elif code in seen:
            fail(f"duplicate hubCode: {code}", failures)
        else:
            seen.add(code)
        for key in ("hubVersion", "platformVersion"):
            value = hub.get(key)
            if not isinstance(value, str) or not SEMVER_PATTERN.fullmatch(value):
                fail(f"invalid {key} for {code or index}: {value!r}", failures)


def validate_json_files(failures: list[str]) -> None:
    for path in sorted((ROOT / "supabase" / "data" / "manifests").glob("*.json")):
        load_json(path, failures)


def validate_config(failures: list[str]) -> None:
    config = (ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
    if 'project_id = "learning-platform-backend"' not in config:
        fail("supabase project_id is not learning-platform-backend", failures)
    if '"admin_api"' not in config:
        fail("admin_api is not declared in the local Data API schema list", failures)


def validate_forbidden_files(failures: list[str]) -> None:
    forbidden_names = {".env", ".temp", ".branches"}
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    for relative in result.stdout.splitlines():
        parts = Path(relative).parts
        if any(part in forbidden_names for part in parts):
            fail(f"forbidden local artefact is tracked: {relative}", failures)


def main() -> int:
    failures: list[str] = []
    validate_paths(failures)
    validate_migrations(failures)
    validate_json_files(failures)
    validate_hub_registry(failures)
    validate_config(failures)
    validate_forbidden_files(failures)

    if failures:
        for message in failures:
            print(f"ERROR: {message}", file=sys.stderr)
        return 1

    migration_count = len(list((ROOT / "supabase" / "migrations").glob("*.sql")))
    manifest_count = len(list((ROOT / "supabase" / "data" / "manifests").glob("*.json")))
    print(f"Repository validation passed: {migration_count} migrations, {manifest_count} manifests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
