# Validation scripts

Run `python3 scripts/validation/validate_repository.py` before database checks.
The validator checks the required repository structure, migration names, all
JSON manifests, every indexed standard hub manifest (including compatibility,
course and conflict checks), Supabase project identity and forbidden local
artefacts.
