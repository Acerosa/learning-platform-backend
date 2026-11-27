begin;
select plan(4);

select has_function(
  'learning',
  'resolve_marking_question',
  array['uuid'],
  'resolve_marking_question remains available after coverage restore'
);

select has_function(
  'platform',
  'marking_spec_from_staff_block',
  array['jsonb'],
  'staff-block marking helper is installed'
);

select has_view(
  'admin_api',
  'published_marking_coverage_gaps',
  'staff marking coverage diagnostic view exists'
);

-- Prefer unique automatic unbound marking over requires_review siblings.
select ok(
  (
    select platform.marking_spec_from_staff_block(
      jsonb_build_object(
        'type', 'single-choice',
        'content', jsonb_build_object('correctOptionId', 'store')
      )
    ) = jsonb_build_object('mode', 'single-choice', 'correctOptionId', 'store')
  ),
  'staff-block helper derives single-choice specs from authoritative content'
);

select * from finish();
rollback;
