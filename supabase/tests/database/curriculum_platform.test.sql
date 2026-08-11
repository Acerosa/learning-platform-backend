begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_table(
  'learning',
  'curriculum_weeks',
  'curriculum weeks table exists'
);

select has_column(
  'learning',
  'curriculum_weeks',
  'week_number',
  'curriculum weeks have a teaching week number'
);

select has_column(
  'learning',
  'activity_delivery',
  'curriculum_week_id',
  'activity delivery can reference a curriculum week'
);

select has_view(
  'api',
  'curriculum_weeks',
  'curriculum weeks are available through the API layer'
);

select * from finish();

rollback;