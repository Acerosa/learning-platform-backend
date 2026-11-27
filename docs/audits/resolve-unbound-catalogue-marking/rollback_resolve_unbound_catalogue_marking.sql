-- Rollback: restore pre-fix resolve_marking_question (no unbound catalogue fallback).
\ir production_before_resolve_marking_question.sql

revoke all on function learning.resolve_marking_question(uuid)
  from public, anon, authenticated;

comment on function learning.resolve_marking_question(uuid) is
  'Resolves a question id to the authoritative marking specification using exact-version compatibility and fingerprint binding only.';
