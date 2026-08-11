#!/usr/bin/env python3
"""Validate one repository-owned Learning Platform hub manifest."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from hub_manifest import ROOT, validate_manifest


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate learning-platform-hub.json before backend registration."
    )
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--contracts",
        type=Path,
        default=ROOT / "supabase/data/manifests/platform-contracts.json",
    )
    parser.add_argument(
        "--manifests-root",
        type=Path,
        default=ROOT / "supabase/data/manifests",
        help="Reviewed curriculum manifests used for course validation.",
    )
    parser.add_argument(
        "--registry",
        type=Path,
        default=ROOT / "supabase/data/manifests/hubs",
        help="Reviewed hub manifests used for conflict detection.",
    )
    parser.add_argument("--json", action="store_true", help="Emit a JSON validation report.")
    args = parser.parse_args()

    report = validate_manifest(
        args.manifest,
        contracts_path=args.contracts,
        manifests_root=args.manifests_root,
        registry_root=args.registry,
    )
    if args.json:
        print(
            json.dumps(
                {
                    "manifest": str(report.manifest_path),
                    "valid": report.valid,
                    "errors": [
                        {"code": issue.code, "path": issue.path, "message": issue.message}
                        for issue in report.issues
                    ],
                },
                indent=2,
            )
        )
    elif report.valid:
        print(f"Hub manifest validation passed: {report.manifest_path}")
    else:
        for issue in report.issues:
            print(f"ERROR: {issue.render()}")
    return 0 if report.valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
