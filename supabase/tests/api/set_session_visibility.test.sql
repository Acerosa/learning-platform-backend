begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

-- Variable-size synthetic packages (not T Level-shaped).
create function pg_temp.visibility_package(
  p_hub text,
  p_course text,
  p_curriculum_id text,
  p_week_count int,
  p_sessions_per_week int,
  p_week_status text default 'available'
)
returns jsonb
language plpgsql
as $$
declare
  v_weeks jsonb := '[]'::jsonb;
  v_sessions jsonb := '[]'::jsonb;
  v_activities jsonb := '[]'::jsonb;
  v_week_ids jsonb := '[]'::jsonb;
  v_w int;
  v_s int;
  v_week_id text;
  v_session_id text;
  v_activity_id text;
  v_session_ids jsonb;
begin
  for v_w in 1..p_week_count loop
    v_week_id := format('vis-week-%s', v_w);
    v_session_ids := '[]'::jsonb;
    for v_s in 1..p_sessions_per_week loop
      v_session_id := format('%s-session-%s', v_week_id, v_s);
      v_activity_id := format('%s-act', v_session_id);
      v_session_ids := v_session_ids || jsonb_build_array(v_session_id);
      v_sessions := v_sessions || jsonb_build_array(jsonb_build_object(
        'schema', 'lp.content.session',
        'schemaVersion', '0.1.0',
        'id', v_session_id,
        'version', '0.1.0',
        'metadata', jsonb_build_object(
          'title', v_session_id,
          'kind', 'session',
          'status', case when v_w = 1 and v_s = 1 then 'available' else 'planned' end
        ),
        'relationships', jsonb_build_object(
          'week', v_week_id,
          'activities', jsonb_build_array(v_activity_id)
        )
      ));
      v_activities := v_activities || jsonb_build_array(jsonb_build_object(
        'schema', 'lp.content.activity',
        'schemaVersion', '0.1.0',
        'id', v_activity_id,
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', v_activity_id, 'status', 'available'),
        'relationships', jsonb_build_object(),
        'blocks', jsonb_build_array(jsonb_build_object(
          'schema', 'lp.content.block',
          'schemaVersion', '0.1.0',
          'id', v_activity_id || '-block',
          'version', '0.1.0',
          'type', 'paragraph',
          'metadata', jsonb_build_object(),
          'relationships', jsonb_build_object(),
          'content', jsonb_build_object('text', 'Synthetic activity body.')
        ))
      ));
    end loop;
    v_week_ids := v_week_ids || jsonb_build_array(v_week_id);
    v_weeks := v_weeks || jsonb_build_array(jsonb_build_object(
      'schema', 'lp.content.week',
      'schemaVersion', '0.1.0',
      'id', v_week_id,
      'version', '0.1.0',
      'metadata', jsonb_build_object(
        'title', format('Week %s', v_w),
        'teachingWeek', v_w,
        'status', case when v_w = 1 then p_week_status else 'planned' end
      ),
      'relationships', jsonb_build_object(
        'sessions', v_session_ids,
        'learningOutcomes', '[]'::jsonb
      )
    ));
  end loop;

  return jsonb_build_object(
    'hub', jsonb_build_object(
      'schema', 'lp.content.hub',
      'schemaVersion', '0.1.0',
      'id', p_hub,
      'version', '0.1.0',
      'metadata', jsonb_build_object('name', p_hub),
      'relationships', jsonb_build_object('curriculum', p_curriculum_id)
    ),
    'curriculum', jsonb_build_object(
      'schema', 'lp.content.curriculum',
      'schemaVersion', '0.1.0',
      'id', p_curriculum_id,
      'version', '0.1.0',
      'metadata', jsonb_build_object('title', p_hub, 'course', p_course),
      'relationships', jsonb_build_object(
        'learningOutcomes', '[]'::jsonb,
        'assignments', '[]'::jsonb,
        'weeks', v_week_ids
      )
    ),
    'learningOutcomes', '[]'::jsonb,
    'assignments', '[]'::jsonb,
    'weeks', v_weeks,
    'sessions', v_sessions,
    'activities', v_activities,
    'questions', '[]'::jsonb,
    'assets', '[]'::jsonb
  );
end;
$$;

select has_function(
  'admin_api',
  'set_session_visibility',
  array['text', 'text', 'text', 'text'],
  'staff API exposes set_session_visibility'
);

select is(platform.bump_patch_version('0.3.30'), '0.3.31', 'patch bump increments catalogue version');

set local role anon;
select throws_like(
  $$select * from admin_api.set_session_visibility(
    'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-2', 'available'
  )$$,
  '%permission denied%',
  'anonymous clients cannot set session visibility'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.set_session_visibility(
    'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-2', 'available'
  )$$,
  '28000',
  'PUBLICATION_NOT_AUTHORISED',
  'a learner cannot set session visibility'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

-- Seed fixture A (Unit 3 shape: 2 weeks × 3 sessions)
select ok(
  (
    select idempotent
    from admin_api.publish_curriculum(
      'published',
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '9.1.0',
      '0.1.0',
      '0.1.0',
      pg_temp.visibility_package(
        'unit-3-cyber-security',
        'ocr-level-3-it',
        'unit-3-cyber-security-curriculum',
        2,
        3,
        'available'
      ),
      'Ada Author',
      'Riley Reviewer',
      'visibility fixture A'
    )
  ) = false,
  'fixture A publishes'
);

select throws_ok(
  $$select * from admin_api.set_session_visibility(
    'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-2', 'open'
  )$$,
  '22023',
  'SESSION_STATUS_INVALID',
  'invalid status blocked'
);

select throws_ok(
  $$select * from admin_api.set_session_visibility(
    'missing-hub', 'ocr-level-3-it', 'vis-week-1-session-2', 'available'
  )$$,
  '22023',
  'HUB_NOT_FOUND',
  'invalid hub blocked'
);

select throws_ok(
  $$select * from admin_api.set_session_visibility(
    'unit-3-cyber-security', 'missing-course', 'vis-week-1-session-2', 'available'
  )$$,
  '22023',
  'COURSE_NOT_FOUND',
  'invalid course blocked'
);

select throws_ok(
  $$select * from admin_api.set_session_visibility(
    'unit-3-cyber-security', 'ocr-level-3-it', 'no-such-session', 'available'
  )$$,
  '22023',
  'SESSION_NOT_FOUND',
  'invalid session blocked'
);

-- Parent planned week blocks posting
select ok(
  (
    select idempotent
    from admin_api.publish_curriculum(
      'published',
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '9.1.1',
      '0.1.0',
      '0.1.0',
      pg_temp.visibility_package(
        'unit-3-cyber-security',
        'ocr-level-3-it',
        'unit-3-cyber-security-curriculum',
        1,
        2,
        'planned'
      ),
      'Ada Author',
      'Riley Reviewer',
      'planned week fixture'
    )
  ) = false,
  'planned-week fixture publishes'
);

select throws_ok(
  $$select * from admin_api.set_session_visibility(
    'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-2', 'available'
  )$$,
  '22023',
  'WEEK_NOT_AVAILABLE',
  'parent planned week blocks posting'
);

-- Restore available-week base for remaining Unit 3 checks
select ok(
  (
    select idempotent
    from admin_api.publish_curriculum(
      'published',
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '9.2.0',
      '0.1.0',
      '0.1.0',
      pg_temp.visibility_package(
        'unit-3-cyber-security',
        'ocr-level-3-it',
        'unit-3-cyber-security-curriculum',
        2,
        3,
        'available'
      ),
      'Ada Author',
      'Riley Reviewer',
      'visibility base 9.2.0'
    )
  ) = false,
  'available-week base publishes as 9.2.0'
);

select results_eq(
  $$select previous_package_version, package_version, session_id, previous_status, status, idempotent
    from admin_api.set_session_visibility(
      'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-2', 'available'
    )$$,
  $$values ('9.2.0'::text, '9.2.1'::text, 'vis-week-1-session-2'::text, 'planned'::text, 'available'::text, false)$$,
  'post planned session → available creates next catalogue version'
);

select is(
  (
    select session_doc->'metadata'->>'status'
    from platform.curriculum_publications as publication,
         jsonb_array_elements(publication.package->'sessions') as session_doc
    where publication.hub_code = 'unit-3-cyber-security'
      and publication.course_key = 'ocr-level-3-it'
      and publication.status = 'published'
      and session_doc->>'id' = 'vis-week-1-session-2'
  ),
  'available',
  'current publication marks target session available'
);

select is(
  (
    select session_doc->'metadata'->>'status'
    from platform.curriculum_publications as publication,
         jsonb_array_elements(publication.package->'sessions') as session_doc
    where publication.hub_code = 'unit-3-cyber-security'
      and publication.course_key = 'ocr-level-3-it'
      and publication.status = 'published'
      and session_doc->>'id' = 'vis-week-1-session-1'
  ),
  'available',
  'unrelated session status preserved'
);

select is(
  (
    select count(*)::int
    from platform.curriculum_publications as publication,
         jsonb_array_elements(publication.package->'sessions') as session_doc
    where publication.status = 'published'
      and publication.hub_code = 'unit-3-cyber-security'
      and publication.course_key = 'ocr-level-3-it'
  ),
  6,
  'full session count preserved after visibility post'
);

select is(
  (
    select publication_notes
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and course_key = 'ocr-level-3-it'
      and status = 'published'
  ),
  'Session visibility: post vis-week-1-session-2',
  'publication notes use existing Session visibility terminology'
);

select is(
  (
    select count(*)::int
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and course_key = 'ocr-level-3-it'
      and package_version = '9.2.0'
      and status = 'superseded'
  ),
  1,
  'previous publication superseded'
);

-- Only metadata.status differs for the target session (deep package compare excluding that path).
select ok(
  (
    with
    prev as (
      select package
      from platform.curriculum_publications
      where hub_code = 'unit-3-cyber-security'
        and course_key = 'ocr-level-3-it'
        and package_version = '9.2.0'
    ),
    curr as (
      select package
      from platform.curriculum_publications
      where hub_code = 'unit-3-cyber-security'
        and course_key = 'ocr-level-3-it'
        and status = 'published'
    ),
    prev_norm as (
      select jsonb_set(
        prev.package,
        '{sessions}',
        (
          select jsonb_agg(
            case
              when s->>'id' = 'vis-week-1-session-2'
                then jsonb_set(s, '{metadata,status}', '"available"'::jsonb, true)
              else s
            end
            order by ordinality
          )
          from jsonb_array_elements(prev.package->'sessions') with ordinality as t(s, ordinality)
        )
      ) as package
      from prev
    )
    select prev_norm.package = curr.package
    from prev_norm, curr
  ),
  'only requested session metadata.status changes versus previous package'
);

select results_eq(
  $$select package_version, previous_status, status, idempotent
    from admin_api.set_session_visibility(
      'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-2', 'available'
    )$$,
  $$values ('9.2.1'::text, 'available'::text, 'available'::text, true)$$,
  'already-at-target returns idempotent without new version'
);

select is(
  (
    select count(*)::int
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and course_key = 'ocr-level-3-it'
      and package_version = '9.2.2'
  ),
  0,
  'no-op creates no unnecessary version'
);

select results_eq(
  $$select previous_package_version, package_version, status, idempotent
    from admin_api.set_session_visibility(
      'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-2', 'planned'
    )$$,
  $$values ('9.2.1'::text, '9.2.2'::text, 'planned'::text, false)$$,
  'remove available session → planned'
);

-- Concurrent sequential posts: A then B both remain available
select ok(
  (
    select status = 'available' and idempotent = false
    from admin_api.set_session_visibility(
      'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-2', 'available'
    )
  ),
  're-post session A after remove'
);

select ok(
  (
    select package_version = '9.2.4' and status = 'available'
    from admin_api.set_session_visibility(
      'unit-3-cyber-security', 'ocr-level-3-it', 'vis-week-1-session-3', 'available'
    )
  ),
  'post session B derives from current catalogue'
);

select ok(
  (
    select bool_and(session_doc->'metadata'->>'status' = 'available')
    from platform.curriculum_publications as publication,
         jsonb_array_elements(publication.package->'sessions') as session_doc
    where publication.status = 'published'
      and publication.hub_code = 'unit-3-cyber-security'
      and publication.course_key = 'ocr-level-3-it'
      and session_doc->>'id' in ('vis-week-1-session-2', 'vis-week-1-session-3')
  ),
  'concurrent Session A + Session B updates preserve both'
);

-- Fixture B: different hub/course/size (Unit 14)
select ok(
  (
    select idempotent = false
    from admin_api.publish_curriculum(
      'published',
      'unit-14-software-engineering-for-business',
      'ocr-level-3-it',
      '8.0.0',
      '0.1.0',
      '0.1.0',
      pg_temp.visibility_package(
        'unit-14-software-engineering-for-business',
        'ocr-level-3-it',
        'unit-14-software-engineering-for-business-curriculum',
        3,
        2,
        'available'
      ),
      'Ada Author',
      'Riley Reviewer',
      'visibility fixture B'
    )
  ),
  'fixture B publishes on second hub'
);

select results_eq(
  $$select previous_package_version, package_version, session_id, status, idempotent
    from admin_api.set_session_visibility(
      'unit-14-software-engineering-for-business', 'ocr-level-3-it', 'vis-week-1-session-2', 'available'
    )$$,
  $$values ('8.0.0'::text, '8.0.1'::text, 'vis-week-1-session-2'::text, 'available'::text, false)$$,
  'second generic hub fixture passes same contract'
);

-- RPC never accepts package JSON (signature check)
select is(
  (
    select count(*)::int
    from pg_proc as proc
    join pg_namespace as nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'admin_api'
      and proc.proname = 'set_session_visibility'
      and pg_get_function_identity_arguments(proc.oid) = 'p_hub_code text, p_course_key text, p_session_id text, p_status text'
  ),
  1,
  'stale client data cannot revert state because package JSON is not accepted'
);

reset role;

select finish();
rollback;
