#!/usr/bin/env python3
"""Generate deterministic migration SQL from a reviewed hub manifest."""

from __future__ import annotations

import argparse
from pathlib import Path

from hub_manifest import (
    HUB_STATUSES,
    ROOT,
    generate_registration_sql,
    load_json,
    manifest_sha256,
    validate_manifest,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a hub manifest and write reviewable registration migration SQL."
    )
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--status", choices=sorted(HUB_STATUSES), default="planned")
    parser.add_argument(
        "--active",
        action="store_true",
        help="Register as active; only valid with testing, production, or maintenance status.",
    )
    parser.add_argument(
        "--contracts",
        type=Path,
        default=ROOT / "supabase/data/manifests/platform-contracts.json",
    )
    parser.add_argument(
        "--manifests-root",
        type=Path,
        default=ROOT / "supabase/data/manifests",
    )
    parser.add_argument(
        "--registry",
        type=Path,
        default=ROOT / "supabase/data/manifests/hubs",
    )
    args = parser.parse_args()

    report = validate_manifest(
        args.manifest,
        contracts_path=args.contracts,
        manifests_root=args.manifests_root,
        registry_root=args.registry,
    )
    if not report.valid:
        for issue in report.issues:
            print(f"ERROR: {issue.render()}")
        return 1

    manifest = load_json(args.manifest)
    sql = generate_registration_sql(manifest, status=args.status, active=args.active)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")
    print(
        f"Generated {args.output}: hub={manifest['hubId']} "
        f"manifest_sha256={manifest_sha256(manifest)} status={args.status} active={args.active}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
