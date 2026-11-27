-- Local seed only: publication seed files insert staff packages after migrations.
-- Re-run the idempotent Phase B backfill so local/CI publications match production
-- expectations for stored learner_package rows.

do $$
declare
  v_row platform.curriculum_publications%rowtype;
  v_learner jsonb;
  v_version text := platform.learner_package_sanitisation_version();
  v_updated int := 0;
begin
  for v_row in
    select publication.*
    from platform.curriculum_publications as publication
    where publication.learner_package is null
       or publication.learner_package_sanitisation_version is distinct from v_version
    order by publication.hub_code, publication.course_key, publication.package_version
    for update
  loop
    v_learner := platform.learner_curriculum_package(
      v_row.package,
      v_row.package_version,
      v_row.source_package_version
    );

    if v_learner is null or jsonb_typeof(v_learner) <> 'object' then
      raise exception
        using errcode = '22023',
              message = format(
                'LEARNER_PACKAGE_SEED_BACKFILL_FAILED:%s:%s:%s',
                v_row.hub_code,
                v_row.course_key,
                v_row.package_version
              );
    end if;

    update platform.curriculum_publications as publication
    set
      learner_package = v_learner,
      learner_package_sanitisation_version = v_version
    where publication.id = v_row.id;

    v_updated := v_updated + 1;
  end loop;

  raise notice 'Local seed learner_package backfill updated % publication(s)', v_updated;
end;
$$;
