#!/usr/bin/env python3
"""Dependency-free structural and manifest validation for this repository."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


IMPORT_DIR = Path(__file__).resolve().parents[1] / "import"
sys.path.insert(0, str(IMPORT_DIR))

from hub_manifest import (  # noqa: E402
    REQUIRED_TOP_LEVEL_KEYS,
    SEMVER_PATTERN,
    STANDARD_MANIFEST_NAME,
    TOP_LEVEL_KEYS,
    conflict_url,
    validate_manifest,
)


ROOT = Path(__file__).resolve().parents[2]
MIGRATION_PATTERN = re.compile(r"^(\d{14})_[a-z0-9_]+\.sql$")
SEED_PATH_PATTERN = re.compile(r'"(\./[^"]+\.sql)"')
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
    "docs/hub-registration.md",
    "docs/backend-publication.md",
    "docs/release-process.md",
    "supabase/data/manifests/schemas/learning-platform-hub.schema.json",
    "scripts/import/validate-hub-manifest.py",
    "scripts/import/generate-hub-registration-migration.py",
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
        "manifestPath",
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
        relative = hub.get("manifestPath")
        if not isinstance(relative, str):
            fail(f"invalid manifest path at item {index}: {relative!r}", failures)
            continue
        target = path.parent / relative
        if not target.is_file() or target.name != STANDARD_MANIFEST_NAME:
            fail(f"missing standard hub manifest for {code or index}: {relative}", failures)
            continue
        manifest = load_json(target, failures)
        if not isinstance(manifest, dict):
            continue
        comparisons = {
            "hubId": (manifest.get("hubId"), code),
            "name": (manifest.get("name"), hub.get("hubName")),
            "version": (manifest.get("version"), hub.get("hubVersion")),
            "coreVersion": (
                manifest.get("compatibility", {}).get("required", {}).get("coreVersion"),
                hub.get("platformVersion"),
            ),
        }
        for label, (standard_value, legacy_value) in comparisons.items():
            if standard_value != legacy_value:
                fail(f"hub registry {label} mismatch for {code}: {relative}", failures)
        for label, standard_key, legacy_key in (
            ("repository", "repositoryUrl", "repository"),
            ("deployment", "deploymentUrl", "deploymentUrl"),
        ):
            standard_url = manifest.get(standard_key)
            legacy_url = hub.get(legacy_key)
            if (
                not isinstance(standard_url, str)
                or not isinstance(legacy_url, str)
                or conflict_url(standard_url) != conflict_url(legacy_url)
            ):
                fail(f"hub registry {label} URL mismatch for {code}: {relative}", failures)
        activities = manifest.get("capabilities", {}).get("activities")
        if not isinstance(activities, list) or set(activities) != set(hub.get("activityTypes", [])):
            fail(f"hub registry activity capability mismatch for {code}: {relative}", failures)
        if manifest.get("featureFlags") != hub.get("features"):
            fail(f"hub registry feature flag mismatch for {code}: {relative}", failures)


def validate_json_files(failures: list[str]) -> None:
    for path in sorted((ROOT / "supabase" / "data" / "manifests").rglob("*.json")):
        load_json(path, failures)


def validate_hub_manifests(failures: list[str]) -> None:
    hub_root = ROOT / "supabase" / "data" / "manifests" / "hubs"
    paths = sorted(hub_root.rglob(STANDARD_MANIFEST_NAME))
    if not paths:
        fail("no reviewed learning-platform-hub.json manifests found", failures)
        return
    for path in paths:
        report = validate_manifest(path)
        for issue in report.issues:
            fail(f"{path.relative_to(ROOT)}: {issue.render()}", failures)


def validate_hub_schema_alignment(failures: list[str]) -> None:
    path = (
        ROOT
        / "supabase/data/manifests/schemas/learning-platform-hub.schema.json"
    )
    schema = load_json(path, failures)
    if not isinstance(schema, dict):
        return
    properties = schema.get("properties")
    required = schema.get("required")
    if not isinstance(properties, dict) or set(properties) != TOP_LEVEL_KEYS:
        fail("hub JSON Schema properties do not match the validator contract", failures)
    if not isinstance(required, list) or set(required) != REQUIRED_TOP_LEVEL_KEYS:
        fail("hub JSON Schema required fields do not match the validator contract", failures)


def validate_config(failures: list[str]) -> None:
    config = (ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
    if 'project_id = "learning-platform-backend"' not in config:
        fail("supabase project_id is not learning-platform-backend", failures)
    if '"admin_api"' not in config:
        fail("admin_api is not declared in the local Data API schema list", failures)


def validate_seed_files(failures: list[str]) -> None:
    config = (ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
    in_seed_paths = False
    for line in config.splitlines():
        stripped = line.strip()
        if stripped.startswith("sql_paths"):
            in_seed_paths = True
            continue
        if not in_seed_paths:
            continue
        if stripped.startswith("]"):
            break
        match = SEED_PATH_PATTERN.search(stripped)
        if not match:
            continue
        relative = match.group(1).removeprefix("./")
        path = ROOT / "supabase" / relative
        if not path.is_file():
            fail(f"missing configured seed file: supabase/{relative}", failures)
            continue
        tracked = subprocess.run(
            ["git", "ls-files", "--error-unmatch", str(path.relative_to(ROOT))],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        if tracked.returncode != 0:
            fail(
                f"configured seed file is not tracked in git: supabase/{relative}",
                failures,
            )


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
    validate_hub_manifests(failures)
    validate_hub_schema_alignment(failures)
    validate_config(failures)
    validate_seed_files(failures)
    validate_forbidden_files(failures)

    if failures:
        for message in failures:
            print(f"ERROR: {message}", file=sys.stderr)
        return 1

    migration_count = len(list((ROOT / "supabase" / "migrations").glob("*.sql")))
    manifest_count = len(list((ROOT / "supabase" / "data" / "manifests").rglob("*.json")))
    print(f"Repository validation passed: {migration_count} migrations, {manifest_count} manifests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
