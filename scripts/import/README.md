# Import scripts

`generate-curriculum-migration.py` converts the current Unit 3 delivery-manifest
shape into a deterministic SQL migration. Generate into
`supabase/data/generated/`, review the SQL and then add it to
`supabase/migrations/` with a new timestamp. A future contract version should
generalise this importer before other manifest shapes depend on it.

The backend repository does not read curriculum source files from a hub. Hubs
own curriculum content; this repository owns reviewed manifests and migrations.
