# Import scripts

`generate-curriculum-migration.py` converts the current Unit 3 delivery-manifest
shape into a deterministic SQL migration. Generate into
`supabase/data/generated/`, review the SQL and then add it to
`supabase/migrations/` with a new timestamp.

`generate-content-package-migration.py` consumes a canonical `lp.content`
package (Unit 14) and writes the same reviewable SQL/JSON pair. It does not
replace the Unit 3 importer. See `docs/content-publication.md`.

`generate-curriculum-publication-seed.py` assembles the same package into a
local `platform.curriculum_publications` seed. Use `--publication-only` when the
hub catalogue is already grounded (Unit 3, T Level). Runtime publication uses
`admin_api.publish_curriculum`, which projects the delivery catalogue.

`convert_static_hubs.mjs` converts Unit 3 / T Level Git teaching snapshots into
canonical `lp.content` packages in each hub's `content/` directory. Pair with
the publication seed generator above for local database-first testing.

```bash
node scripts/import/convert_static_hubs.mjs
python3 scripts/import/generate-curriculum-publication-seed.py --publication-only \
  ../unit-3-Cyber-Security-Hub/content/unit-3-cyber-security \
  supabase/data/generated/seed-unit3-publication.sql
node scripts/import/tests/test_static_hub_packages.mjs
```

See `docs/curriculum-migration-unit3-tlevel.md` for the full migration record.

`validate-hub-manifest.py` validates the LHDS root
`learning-platform-hub.json`, including conflicts, course identities and active
compatibility versions. `generate-hub-registration-migration.py` converts a
valid reviewed manifest into deterministic SQL. It defaults to a planned,
inactive registration and cannot deploy or modify a database.

```bash
python3 scripts/import/validate-hub-manifest.py /path/to/learning-platform-hub.json
python3 scripts/import/generate-hub-registration-migration.py \
  /path/to/learning-platform-hub.json \
  supabase/data/generated/register-hub.sql
python3 scripts/import/generate-content-package-migration.py \
  /path/to/content/unit-14 \
  supabase/data/generated/import-content-package.sql
python3 -m unittest discover -s scripts/import/tests -p 'test_*.py'
```

The backend repository does not read curriculum source files from a hub. Hubs
own curriculum content; this repository owns reviewed manifests and migrations.
