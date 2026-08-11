# Import scripts

`generate-curriculum-migration.py` converts the current Unit 3 delivery-manifest
shape into a deterministic SQL migration. Generate into
`supabase/data/generated/`, review the SQL and then add it to
`supabase/migrations/` with a new timestamp. A future contract version should
generalise this importer before other manifest shapes depend on it.

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
python3 -m unittest discover -s scripts/import/tests -p 'test_*.py'
```

The backend repository does not read curriculum source files from a hub. Hubs
own curriculum content; this repository owns reviewed manifests and migrations.
