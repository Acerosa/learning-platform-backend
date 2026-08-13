#!/usr/bin/env python3
"""Validate a canonical content package and write reviewable catalogue SQL."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from content_package import (
    PackageError,
    build_registration,
    canonical_json,
    generate_sql,
    load_package,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate canonical curriculum JSON and generate a reviewed backend catalogue migration."
    )
    parser.add_argument("package", type=Path, help="Directory containing index.json")
    parser.add_argument("output", type=Path, help="SQL output path, normally under supabase/data/generated/")
    parser.add_argument(
        "--json",
        dest="json_output",
        type=Path,
        help="Optional registration artefact JSON path",
    )
    args = parser.parse_args()

    try:
        package = load_package(args.package)
        registration = build_registration(package)
    except PackageError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    sql = generate_sql(registration)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")
    if args.json_output is not None:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(canonical_json(registration) + "\n", encoding="utf-8")

    print(
        f"Generated {args.output}: hub={registration['provenance']['hubId']} "
        f"weeks={len(registration['weeks'])} activities={len(registration['activities'])} "
        f"assignments_hub_only={len(registration['assignments'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
