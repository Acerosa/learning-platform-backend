#!/usr/bin/env python3
"""Validate LHDS hub manifests and generate reviewed registration SQL."""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Any, Iterable
from urllib.parse import urlsplit, urlunsplit
import uuid


ROOT = Path(__file__).resolve().parents[2]
STANDARD_MANIFEST_NAME = "learning-platform-hub.json"
SUPPORTED_MANIFEST_VERSION = "1.0.0"
HUB_NAMESPACE = uuid.UUID("9af81199-041c-4a96-90d6-778850dd81f6")

STABLE_KEY_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
FEATURE_FLAG_PATTERN = re.compile(r"^[a-z][A-Za-z0-9]*$")
SEMVER_PATTERN = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)

TOP_LEVEL_KEYS = {
    "manifestVersion",
    "hubId",
    "name",
    "description",
    "version",
    "repositoryUrl",
    "deploymentUrl",
    "courses",
    "compatibility",
    "capabilities",
    "featureFlags",
    "certification",
}
REQUIRED_TOP_LEVEL_KEYS = TOP_LEVEL_KEYS - {"certification"}
VERSION_KEYS = {
    "coreVersion": "learning-platform-core",
    "learnerApiContractVersion": "learner-api",
    "submissionContractVersion": "submission",
}
HUB_STATUSES = {
    "planned",
    "development",
    "testing",
    "production",
    "maintenance",
    "deprecated",
    "archived",
}


class ManifestLoadError(ValueError):
    """Raised when JSON cannot be loaded without ambiguity."""


@dataclass(frozen=True, order=True)
class ValidationIssue:
    code: str
    path: str
    message: str

    def render(self) -> str:
        return f"{self.code} at {self.path}: {self.message}"


@dataclass(frozen=True)
class ValidationReport:
    manifest_path: Path
    issues: tuple[ValidationIssue, ...]

    @property
    def valid(self) -> bool:
        return not self.issues

    def require_valid(self) -> None:
        if self.issues:
            raise ValueError("\n".join(issue.render() for issue in self.issues))


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ManifestLoadError(f"duplicate JSON property: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ManifestLoadError) as error:
        raise ManifestLoadError(f"cannot load {path}: {error}") from error


def canonical_manifest(manifest: dict[str, Any]) -> str:
    return json.dumps(
        manifest,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def manifest_sha256(manifest: dict[str, Any]) -> str:
    return sha256(canonical_manifest(manifest).encode("utf-8")).hexdigest()


def deterministic_hub_id(hub_id: str) -> str:
    return str(uuid.uuid5(HUB_NAMESPACE, f"hub:{hub_id}"))


def normalize_url(value: str) -> str:
    parsed = urlsplit(value)
    host = (parsed.hostname or "").lower()
    port = f":{parsed.port}" if parsed.port else ""
    netloc = host + port
    path = parsed.path.rstrip("/") or ""
    return urlunsplit((parsed.scheme.lower(), netloc, path, "", ""))


def conflict_url(value: str) -> str:
    return normalize_url(value).lower()


def _issue(
    issues: list[ValidationIssue], code: str, path: str, message: str
) -> None:
    issues.append(ValidationIssue(code, path, message))


def _object(
    value: Any,
    path: str,
    issues: list[ValidationIssue],
    required: set[str],
    allowed: set[str],
) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        _issue(issues, "SCHEMA_TYPE", path, "must be an object")
        return None
    for key in sorted(required - value.keys()):
        _issue(issues, "SCHEMA_REQUIRED", f"{path}.{key}", "is required")
    for key in sorted(value.keys() - allowed):
        _issue(issues, "SCHEMA_UNKNOWN_FIELD", f"{path}.{key}", "is not allowed")
    return value


def _string(
    value: Any,
    path: str,
    issues: list[ValidationIssue],
    *,
    maximum: int,
) -> str | None:
    if not isinstance(value, str):
        _issue(issues, "SCHEMA_TYPE", path, "must be a string")
        return None
    if not value or value != value.strip():
        _issue(issues, "NAMING_CONVENTION", path, "must be non-blank without surrounding whitespace")
        return None
    if len(value) > maximum:
        _issue(issues, "SCHEMA_LENGTH", path, f"must not exceed {maximum} characters")
    return value


def _stable_key(value: Any, path: str, issues: list[ValidationIssue]) -> str | None:
    text = _string(value, path, issues, maximum=128)
    if text is not None and not STABLE_KEY_PATTERN.fullmatch(text):
        _issue(issues, "NAMING_CONVENTION", path, "must be a lower-case kebab-case stable key")
        return None
    return text


def _semver(value: Any, path: str, issues: list[ValidationIssue]) -> str | None:
    text = _string(value, path, issues, maximum=128)
    if text is not None and not SEMVER_PATTERN.fullmatch(text):
        _issue(issues, "INVALID_SEMVER", path, "must be a Semantic Versioning 2.0.0 version")
        return None
    return text


def _https_url(value: Any, path: str, issues: list[ValidationIssue]) -> str | None:
    text = _string(value, path, issues, maximum=2048)
    if text is None:
        return None
    try:
        parsed = urlsplit(text)
        port = parsed.port
    except ValueError:
        parsed = None
        port = None
    if (
        parsed is None
        or parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or any(character.isspace() for character in text)
        or port not in (None, 443)
    ):
        _issue(
            issues,
            "INVALID_URL",
            path,
            "must be an HTTPS URL without credentials, query, fragment, whitespace, or a non-default port",
        )
        return None
    if parsed.path.endswith("/"):
        _issue(issues, "URL_NOT_CANONICAL", path, "must not have a trailing slash")
    return text


def _stable_key_array(
    value: Any, path: str, issues: list[ValidationIssue]
) -> list[str] | None:
    if not isinstance(value, list):
        _issue(issues, "SCHEMA_TYPE", path, "must be an array")
        return None
    if not value:
        _issue(issues, "SCHEMA_MIN_ITEMS", path, "must contain at least one item")
    result: list[str] = []
    for index, item in enumerate(value):
        stable_key = _stable_key(item, f"{path}[{index}]", issues)
        if stable_key is not None:
            result.append(stable_key)
    duplicates = sorted({item for item in result if result.count(item) > 1})
    for duplicate in duplicates:
        _issue(issues, "SCHEMA_UNIQUE_ITEMS", path, f"contains duplicate value {duplicate!r}")
    if result != sorted(result):
        _issue(issues, "NON_CANONICAL_ORDER", path, "must be sorted lexicographically")
    return result


def _platform_versions(
    value: Any, path: str, issues: list[ValidationIssue]
) -> dict[str, Any] | None:
    result = _object(value, path, issues, set(VERSION_KEYS), set(VERSION_KEYS))
    if result is None:
        return None
    for key in VERSION_KEYS:
        if key in result:
            _semver(result[key], f"{path}.{key}", issues)
    return result


def _validate_compatibility(
    value: Any, issues: list[ValidationIssue]
) -> dict[str, Any] | None:
    path = "$.compatibility"
    compatibility = _object(
        value,
        path,
        issues,
        {"required", "testedCombinations"},
        {"required", "testedCombinations"},
    )
    if compatibility is None:
        return None
    required = _platform_versions(compatibility.get("required"), f"{path}.required", issues)
    tested = compatibility.get("testedCombinations")
    if not isinstance(tested, list):
        _issue(issues, "SCHEMA_TYPE", f"{path}.testedCombinations", "must be an array")
    elif not tested:
        _issue(issues, "SCHEMA_MIN_ITEMS", f"{path}.testedCombinations", "must contain at least one item")
    else:
        canonical_seen: set[str] = set()
        required_canonical = canonical_manifest(required) if required is not None else None
        for index, combination in enumerate(tested):
            parsed = _platform_versions(
                combination, f"{path}.testedCombinations[{index}]", issues
            )
            if parsed is not None:
                canonical = canonical_manifest(parsed)
                if canonical in canonical_seen:
                    _issue(
                        issues,
                        "SCHEMA_UNIQUE_ITEMS",
                        f"{path}.testedCombinations[{index}]",
                        "duplicates an earlier tested combination",
                    )
                canonical_seen.add(canonical)
        if required_canonical is not None and required_canonical not in canonical_seen:
            _issue(
                issues,
                "REQUIRED_COMBINATION_NOT_TESTED",
                f"{path}.testedCombinations",
                "must include the exact required platform version combination",
            )
    return compatibility


def _validate_capabilities(value: Any, issues: list[ValidationIssue]) -> None:
    capabilities = _object(
        value,
        "$.capabilities",
        issues,
        {"evidence", "activities"},
        {"evidence", "activities"},
    )
    if capabilities is None:
        return
    for key in ("evidence", "activities"):
        if key in capabilities:
            _stable_key_array(capabilities[key], f"$.capabilities.{key}", issues)


def _validate_feature_flags(value: Any, issues: list[ValidationIssue]) -> None:
    if not isinstance(value, dict):
        _issue(issues, "SCHEMA_TYPE", "$.featureFlags", "must be an object")
        return
    for key, enabled in value.items():
        if not isinstance(key, str) or not FEATURE_FLAG_PATTERN.fullmatch(key):
            _issue(
                issues,
                "NAMING_CONVENTION",
                f"$.featureFlags.{key}",
                "must be a lower-camel-case flag name",
            )
        if not isinstance(enabled, bool):
            _issue(issues, "SCHEMA_TYPE", f"$.featureFlags.{key}", "must be a boolean")


def _validate_certification(value: Any, issues: list[ValidationIssue]) -> None:
    allowed = {"standard", "version", "status", "reviewedAt", "reviewer", "evidenceUrls"}
    certification = _object(
        value,
        "$.certification",
        issues,
        {"standard", "version", "status"},
        allowed,
    )
    if certification is None:
        return
    if certification.get("standard") != "LHDS":
        _issue(issues, "INVALID_CERTIFICATION", "$.certification.standard", "must equal LHDS")
    if "version" in certification:
        _semver(certification["version"], "$.certification.version", issues)
    valid_statuses = {"not-certified", "in-review", "certified", "expired", "revoked"}
    if certification.get("status") not in valid_statuses:
        _issue(
            issues,
            "INVALID_CERTIFICATION",
            "$.certification.status",
            f"must be one of {', '.join(sorted(valid_statuses))}",
        )
    if "reviewer" in certification:
        _string(certification["reviewer"], "$.certification.reviewer", issues, maximum=160)
    if "reviewedAt" in certification:
        reviewed_at = certification["reviewedAt"]
        if not isinstance(reviewed_at, str) or not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z", reviewed_at
        ):
            _issue(
                issues,
                "INVALID_DATETIME",
                "$.certification.reviewedAt",
                "must be an RFC 3339 UTC date-time",
            )
    if "evidenceUrls" in certification:
        urls = certification["evidenceUrls"]
        if not isinstance(urls, list):
            _issue(issues, "SCHEMA_TYPE", "$.certification.evidenceUrls", "must be an array")
        else:
            seen: set[str] = set()
            for index, url in enumerate(urls):
                parsed = _https_url(url, f"$.certification.evidenceUrls[{index}]", issues)
                if parsed is not None:
                    normalized = conflict_url(parsed)
                    if normalized in seen:
                        _issue(
                            issues,
                            "SCHEMA_UNIQUE_ITEMS",
                            "$.certification.evidenceUrls",
                            f"contains duplicate URL {parsed!r}",
                        )
                    seen.add(normalized)


def _active_contracts(contracts_path: Path, issues: list[ValidationIssue]) -> set[tuple[str, str]]:
    try:
        data = load_json(contracts_path)
    except ManifestLoadError as error:
        _issue(issues, "CONTRACT_CATALOGUE_INVALID", "$", str(error))
        return set()
    if not isinstance(data, dict) or not isinstance(data.get("contracts"), list):
        _issue(
            issues,
            "CONTRACT_CATALOGUE_INVALID",
            "$",
            f"{contracts_path} must contain a contracts array",
        )
        return set()
    result: set[tuple[str, str]] = set()
    for contract in data["contracts"]:
        if isinstance(contract, dict) and contract.get("status") == "active":
            key = contract.get("contractKey")
            version = contract.get("version")
            if isinstance(key, str) and isinstance(version, str):
                result.add((key, version))
    return result


def discover_course_keys(manifests_root: Path) -> set[str]:
    result: set[str] = set()
    for path in sorted(manifests_root.rglob("*.json")):
        if STANDARD_MANIFEST_NAME in path.parts or "schemas" in path.parts:
            continue
        try:
            data = load_json(path)
        except ManifestLoadError:
            continue
        if isinstance(data, dict) and isinstance(data.get("course"), dict):
            stable_key = data["course"].get("stableKey")
            if isinstance(stable_key, str) and STABLE_KEY_PATTERN.fullmatch(stable_key):
                result.add(stable_key)
    return result


def _registry_manifests(registry_root: Path) -> Iterable[tuple[Path, dict[str, Any]]]:
    if not registry_root.exists():
        return
    for path in sorted(registry_root.rglob(STANDARD_MANIFEST_NAME)):
        try:
            manifest = load_json(path)
        except ManifestLoadError:
            continue
        if isinstance(manifest, dict):
            yield path, manifest


def validate_manifest(
    manifest_path: Path,
    *,
    contracts_path: Path | None = None,
    manifests_root: Path | None = None,
    registry_root: Path | None = None,
) -> ValidationReport:
    manifest_path = manifest_path.resolve()
    contracts_path = contracts_path or ROOT / "supabase/data/manifests/platform-contracts.json"
    manifests_root = manifests_root or ROOT / "supabase/data/manifests"
    registry_root = registry_root or ROOT / "supabase/data/manifests/hubs"
    issues: list[ValidationIssue] = []

    try:
        manifest = load_json(manifest_path)
    except ManifestLoadError as error:
        _issue(issues, "INVALID_JSON", "$", str(error))
        return ValidationReport(manifest_path, tuple(sorted(issues)))

    manifest = _object(
        manifest,
        "$",
        issues,
        REQUIRED_TOP_LEVEL_KEYS,
        TOP_LEVEL_KEYS,
    )
    if manifest is None:
        return ValidationReport(manifest_path, tuple(sorted(issues)))

    manifest_version = _semver(manifest.get("manifestVersion"), "$.manifestVersion", issues)
    hub_id = _stable_key(manifest.get("hubId"), "$.hubId", issues)
    _string(manifest.get("name"), "$.name", issues, maximum=160)
    _string(manifest.get("description"), "$.description", issues, maximum=1000)
    _semver(manifest.get("version"), "$.version", issues)
    repository_url = _https_url(manifest.get("repositoryUrl"), "$.repositoryUrl", issues)
    deployment_url = _https_url(manifest.get("deploymentUrl"), "$.deploymentUrl", issues)
    courses = _stable_key_array(manifest.get("courses"), "$.courses", issues)
    compatibility = _validate_compatibility(manifest.get("compatibility"), issues)
    _validate_capabilities(manifest.get("capabilities"), issues)
    _validate_feature_flags(manifest.get("featureFlags"), issues)
    if "certification" in manifest:
        _validate_certification(manifest["certification"], issues)

    active_contracts = _active_contracts(contracts_path, issues)
    if manifest_version is not None and ("hub-manifest", manifest_version) not in active_contracts:
        _issue(
            issues,
            "UNSUPPORTED_MANIFEST_VERSION",
            "$.manifestVersion",
            f"hub-manifest {manifest_version} is not active in the platform contract catalogue",
        )
    if manifest_version is not None and manifest_version != SUPPORTED_MANIFEST_VERSION:
        _issue(
            issues,
            "VALIDATOR_VERSION_MISMATCH",
            "$.manifestVersion",
            f"this validator supports {SUPPORTED_MANIFEST_VERSION}",
        )
    if isinstance(compatibility, dict) and isinstance(compatibility.get("required"), dict):
        required = compatibility["required"]
        for field, contract_key in VERSION_KEYS.items():
            version = required.get(field)
            if isinstance(version, str) and SEMVER_PATTERN.fullmatch(version):
                if (contract_key, version) not in active_contracts:
                    _issue(
                        issues,
                        "UNSUPPORTED_PLATFORM_VERSION",
                        f"$.compatibility.required.{field}",
                        f"{contract_key} {version} is not active in the platform contract catalogue",
                    )

    known_courses = discover_course_keys(manifests_root)
    if courses is not None:
        for index, course in enumerate(courses):
            if course not in known_courses:
                _issue(
                    issues,
                    "UNKNOWN_COURSE",
                    f"$.courses[{index}]",
                    f"{course!r} is not present in a reviewed curriculum manifest",
                )

    if hub_id is not None and repository_url is not None and deployment_url is not None:
        candidate_repository = conflict_url(repository_url)
        candidate_deployment = conflict_url(deployment_url)
        for registered_path, registered in _registry_manifests(registry_root):
            try:
                same_file = registered_path.resolve() == manifest_path
            except OSError:
                same_file = False
            if same_file:
                continue
            registered_id = registered.get("hubId")
            registered_repository = registered.get("repositoryUrl")
            registered_deployment = registered.get("deploymentUrl")
            if registered_id == hub_id:
                _issue(
                    issues,
                    "DUPLICATE_HUB_ID",
                    "$.hubId",
                    f"already registered by {registered_path}",
                )
            if isinstance(registered_repository, str) and conflict_url(registered_repository) == candidate_repository:
                _issue(
                    issues,
                    "DUPLICATE_REPOSITORY",
                    "$.repositoryUrl",
                    f"already registered to {registered_id!r}",
                )
            if isinstance(registered_deployment, str) and conflict_url(registered_deployment) == candidate_deployment:
                _issue(
                    issues,
                    "DUPLICATE_DEPLOYMENT",
                    "$.deploymentUrl",
                    f"already registered to {registered_id!r}",
                )

    return ValidationReport(manifest_path, tuple(sorted(set(issues))))


def sql_literal(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    return "'" + str(value).replace("'", "''") + "'"


def sql_text_array(values: Iterable[str]) -> str:
    items = ", ".join(sql_literal(value) for value in sorted(values))
    return f"array[{items}]::text[]"


def generate_registration_sql(
    manifest: dict[str, Any], *, status: str = "planned", active: bool = False
) -> str:
    if status not in HUB_STATUSES:
        raise ValueError(f"unsupported hub lifecycle status: {status}")
    if active and status not in {"testing", "production", "maintenance"}:
        raise ValueError("active hubs must have testing, production, or maintenance status")

    hub_id = manifest["hubId"]
    required = manifest["compatibility"]["required"]
    canonical = canonical_manifest(manifest)
    digest = manifest_sha256(manifest)
    database_id = deterministic_hub_id(hub_id)
    repository_url = normalize_url(manifest["repositoryUrl"])
    deployment_url = normalize_url(manifest["deploymentUrl"])
    courses = sorted(manifest["courses"])
    compatibility_json = canonical_manifest(manifest["compatibility"])
    feature_flags_json = canonical_manifest(manifest["featureFlags"])
    capability_activities = manifest["capabilities"]["activities"]
    capability_evidence = manifest["capabilities"]["evidence"]

    assertions = [
        ("hub-manifest", manifest["manifestVersion"], "HUB_MANIFEST_VERSION_UNSUPPORTED"),
        ("learning-platform-core", required["coreVersion"], "HUB_CORE_VERSION_UNSUPPORTED"),
        ("learner-api", required["learnerApiContractVersion"], "HUB_LEARNER_API_VERSION_UNSUPPORTED"),
        ("submission", required["submissionContractVersion"], "HUB_SUBMISSION_VERSION_UNSUPPORTED"),
    ]
    lines = [
        "-- Generated by scripts/import/generate-hub-registration-migration.py.",
        f"-- Hub: {hub_id}",
        f"-- Canonical manifest SHA-256: {digest}",
        "-- Review this file before adding it to supabase/migrations/. It never deploys itself.",
        "begin;",
        "",
        "select pg_catalog.pg_advisory_xact_lock(",
        f"  pg_catalog.hashtextextended({sql_literal('hub-registration:' + hub_id)}, 0)",
        ");",
        "",
        "do $$",
        "begin",
    ]
    for contract_key, version, error_code in assertions:
        lines.extend(
            [
                "  if not exists (",
                "    select 1",
                "    from platform.contract_versions as contract",
                f"    where contract.contract_key = {sql_literal(contract_key)}",
                f"      and contract.version = {sql_literal(version)}",
                "      and contract.status = 'active'",
                "  ) then",
                f"    raise exception using errcode = '23514', message = {sql_literal(error_code)};",
                "  end if;",
            ]
        )
    for course in courses:
        lines.extend(
            [
                "  if not exists (",
                "    select 1 from learning.courses as course",
                f"    where course.stable_key = {sql_literal(course)} and course.active",
                "  ) then",
                f"    raise exception using errcode = '23514', message = {sql_literal('HUB_COURSE_NOT_FOUND:' + course)};",
                "  end if;",
            ]
        )
    lines.extend(
        [
            "end",
            "$$;",
            "",
            "insert into platform.hubs (",
            "  id, hub_code, hub_name, description, hub_version, platform_version,",
            "  manifest_version, core_version, learner_api_version, submission_contract_version,",
            "  repository_url, deployment_url, activity_types, evidence_capabilities,",
            "  features, compatibility, status, active, manifest, manifest_sha256",
            ") values (",
            f"  {sql_literal(database_id)},",
            f"  {sql_literal(hub_id)},",
            f"  {sql_literal(manifest['name'])},",
            f"  {sql_literal(manifest['description'])},",
            f"  {sql_literal(manifest['version'])},",
            f"  {sql_literal(required['coreVersion'])},",
            f"  {sql_literal(manifest['manifestVersion'])},",
            f"  {sql_literal(required['coreVersion'])},",
            f"  {sql_literal(required['learnerApiContractVersion'])},",
            f"  {sql_literal(required['submissionContractVersion'])},",
            f"  {sql_literal(repository_url)},",
            f"  {sql_literal(deployment_url)},",
            f"  {sql_text_array(capability_activities)},",
            f"  {sql_text_array(capability_evidence)},",
            f"  {sql_literal(feature_flags_json)}::jsonb,",
            f"  {sql_literal(compatibility_json)}::jsonb,",
            f"  {sql_literal(status)},",
            f"  {sql_literal(active)},",
            f"  {sql_literal(canonical)}::jsonb,",
            f"  {sql_literal(digest)}",
            ")",
            "on conflict (hub_code) do update set",
            "  hub_name = excluded.hub_name,",
            "  description = excluded.description,",
            "  hub_version = excluded.hub_version,",
            "  platform_version = excluded.platform_version,",
            "  manifest_version = excluded.manifest_version,",
            "  core_version = excluded.core_version,",
            "  learner_api_version = excluded.learner_api_version,",
            "  submission_contract_version = excluded.submission_contract_version,",
            "  repository_url = excluded.repository_url,",
            "  deployment_url = excluded.deployment_url,",
            "  activity_types = excluded.activity_types,",
            "  evidence_capabilities = excluded.evidence_capabilities,",
            "  features = excluded.features,",
            "  compatibility = excluded.compatibility,",
            "  status = excluded.status,",
            "  active = excluded.active,",
            "  manifest = excluded.manifest,",
            "  manifest_sha256 = excluded.manifest_sha256,",
            "  updated_at = clock_timestamp();",
            "",
            "update platform.hub_course_links as link",
            "set active = false",
            "where link.hub_id = (select id from platform.hubs where hub_code = "
            + sql_literal(hub_id)
            + ")",
            "  and link.course_id not in (",
            "    select course.id from learning.courses as course",
            "    where course.stable_key = any ("
            + sql_text_array(courses)
            + ")",
            "  );",
            "",
        ]
    )
    for course in courses:
        lines.extend(
            [
                "insert into platform.hub_course_links (hub_id, course_id, active)",
                "select hub.id, course.id, true",
                "from platform.hubs as hub",
                "join learning.courses as course",
                f"  on course.stable_key = {sql_literal(course)}",
                f"where hub.hub_code = {sql_literal(hub_id)}",
                "on conflict (hub_id, course_id) do update set active = true;",
                "",
            ]
        )
    lines.extend(["commit;", ""])
    return "\n".join(lines)
