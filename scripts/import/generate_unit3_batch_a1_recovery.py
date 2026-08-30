#!/usr/bin/env python3
"""Generate the Batch A1 hosted-recovery migration.

Completes the truncated hosted apply of
20260830220000_unit3_batch_a1_canonical_catalogue.sql without rewriting
schema_migrations or mutating published 1.0.0 / learner evidence.

Known compatible unpublished residue:
  u3-w01-baseline 1.1.0 id 0228c12e-1ac3-5c07-ad9f-7c24d355c858
  unpublished, question_count 10, zero questions, no dependents.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

IMPORT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(IMPORT_DIR))

from generate_unit3_batch_a1 import (  # noqa: E402
    COURSE_KEY,
    LIVE_ID_TO_KEY,
    MODULE_KEY,
    NEW_OCR_VERSION,
    NEW_WEEK1_VERSION,
    OCR_V100_QUESTIONS,
    PUBLISHED_AT,
    WEEK1_DELIVERY,
    WEEK5_ACTIVITIES,
    WEEK5_VERSION,
    content_hash,
    deterministic_id,
    module_select,
    sql_literal,
    week1_questions,
    week_select,
)


RESIDUE_ACTIVITY_KEY = "u3-w01-baseline"


def build_catalogue(manifest_dir: Path) -> list[dict]:
    live = json.loads((manifest_dir / "week1-live-banks.json").read_text(encoding="utf-8"))
    week5 = json.loads((manifest_dir / "week5-four-activities.json").read_text(encoding="utf-8"))
    ocr_q08 = json.loads((manifest_dir / "week2-ocr-q08.json").read_text(encoding="utf-8"))
    items: list[dict] = []

    for live_id, activity_key in LIVE_ID_TO_KEY.items():
        questions = week1_questions(live[live_id])
        version = NEW_WEEK1_VERSION
        version_id = deterministic_id("version", f"{activity_key}:{version}")
        payload = {
            "activityKey": activity_key,
            "version": version,
            "source": "live-getActivity",
            "questions": questions,
        }
        items.append(
            _version_item(
                kind="existing_activity",
                activity_key=activity_key,
                version=version,
                version_id=version_id,
                content_hash_value=content_hash(payload),
                questions=questions,
                week_no=1,
                session_number=WEEK1_DELIVERY[activity_key],
                allow_empty_unpublished=(activity_key == RESIDUE_ACTIVITY_KEY),
            )
        )

    ocr_key = "week2-ocr-question-practice"
    ocr_questions = [
        {
            "stableKey": stable_key,
            "sectionKey": "questions",
            "sectionTitle": "Questions",
            "questionType": question_type,
            "analyticsTitle": stable_key,
            "ordinal": ordinal,
            "maxScore": max_score,
            "marking": None,
        }
        for stable_key, question_type, ordinal, max_score in OCR_V100_QUESTIONS
    ]
    ocr_questions.append(
        {
            "stableKey": ocr_q08["stableKey"],
            "sectionKey": ocr_q08["sectionKey"],
            "sectionTitle": ocr_q08["sectionTitle"],
            "questionType": ocr_q08["questionType"],
            "analyticsTitle": ocr_q08["stableKey"],
            "ordinal": ocr_q08["ordinal"],
            "maxScore": ocr_q08["maxScore"],
            "marking": None,
        }
    )
    items.append(
        _version_item(
            kind="existing_activity",
            activity_key=ocr_key,
            version=NEW_OCR_VERSION,
            version_id=deterministic_id("version", f"{ocr_key}:{NEW_OCR_VERSION}"),
            content_hash_value=content_hash(
                {"activityKey": ocr_key, "version": NEW_OCR_VERSION, "questions": ocr_questions}
            ),
            questions=ocr_questions,
            week_no=2,
            session_number=2,
            allow_empty_unpublished=False,
        )
    )

    for meta in WEEK5_ACTIVITIES:
        activity_key = meta["stableKey"]
        source = week5[activity_key]
        questions = []
        for index, raw in enumerate(source["questions"], start=1):
            marking = None
            if raw["questionType"] == "single" and raw.get("correctOptionId"):
                marking = {"mode": "single-choice", "correctOptionId": raw["correctOptionId"]}
            elif raw["questionType"] == "matching" and raw.get("correctCategoryId"):
                marking = {"mode": "classification", "correctCategoryId": raw["correctCategoryId"]}
            questions.append(
                {
                    "stableKey": raw["stableKey"],
                    "sectionKey": meta["sectionKey"],
                    "sectionTitle": meta["sectionTitle"],
                    "questionType": raw["questionType"],
                    "analyticsTitle": raw["stableKey"],
                    "ordinal": index,
                    "maxScore": 1,
                    "marking": marking,
                }
            )
        items.append(
            _version_item(
                kind="new_activity",
                activity_key=activity_key,
                version=WEEK5_VERSION,
                version_id=deterministic_id("version", f"{activity_key}:{WEEK5_VERSION}"),
                content_hash_value=content_hash(
                    {"activityKey": activity_key, "version": WEEK5_VERSION, "questions": questions}
                ),
                questions=questions,
                week_no=5,
                session_number=meta["sessionNumber"],
                allow_empty_unpublished=False,
                activity_id=deterministic_id("activity", f"{COURSE_KEY}:{MODULE_KEY}:{activity_key}"),
                title=meta["title"],
                git_path=meta["gitPath"],
            )
        )
    return items


def _version_item(
    *,
    kind: str,
    activity_key: str,
    version: str,
    version_id: str,
    content_hash_value: str,
    questions: list[dict],
    week_no: int,
    session_number: int,
    allow_empty_unpublished: bool,
    activity_id: str | None = None,
    title: str | None = None,
    git_path: str | None = None,
) -> dict:
    encoded_questions = []
    for question in questions:
        encoded_questions.append(
            {
                "id": deterministic_id("question", f"{activity_key}:{version}:{question['stableKey']}"),
                "stableKey": question["stableKey"],
                "sectionKey": question["sectionKey"],
                "sectionTitle": question["sectionTitle"],
                "questionType": question["questionType"],
                "analyticsTitle": question["analyticsTitle"],
                "ordinal": question["ordinal"],
                "maxScore": question["maxScore"],
                "marking": question.get("marking"),
            }
        )
    item = {
        "kind": kind,
        "activityKey": activity_key,
        "version": version,
        "versionId": version_id,
        "contentHash": content_hash_value,
        "maxScore": sum(question["maxScore"] for question in questions),
        "questionCount": len(questions),
        "weekNumber": week_no,
        "sessionNumber": session_number,
        "allowEmptyUnpublished": allow_empty_unpublished,
        "assignmentId": deterministic_id("assignment", f"CYBER-TEST-A:{activity_key}:{version}"),
        "questions": encoded_questions,
    }
    if kind == "new_activity":
        item["activityId"] = activity_id
        item["title"] = title
        item["gitPath"] = git_path
    return item


def generate_recovery(manifest_dir: Path) -> str:
    catalogue = build_catalogue(manifest_dir)
    catalogue_json = json.dumps(catalogue, separators=(",", ":"), ensure_ascii=False)
    module_sql = module_select()
    week1_sql = week_select(1)
    week2_sql = week_select(2)
    week5_sql = week_select(5)
    return f"""-- Generated by scripts/import/generate_unit3_batch_a1_recovery.py; do not edit manually.
-- Recovers the truncated hosted apply of unit3_batch_a1_canonical_catalogue.
-- Does not rewrite migration history, published 1.0.0 rows, learner evidence,
-- or curriculum publications.
begin;

create or replace function learning.apply_unit3_batch_a1_recovery()
returns void
language plpgsql
set search_path = ''
as $recovery$
declare
  catalogue jsonb := $a1catalogue${catalogue_json}$a1catalogue$;
  item jsonb;
  question jsonb;
  v_activity learning.activities%rowtype;
  v_version learning.activity_versions%rowtype;
  v_activity_id uuid;
  v_question_rows integer;
  v_attempts integer;
  v_delivery integer;
  v_assignments integer;
  v_languages integer;
  v_expected_count integer;
  v_week_id uuid;
begin
  for item in
    select value from jsonb_array_elements(catalogue)
  loop
    v_expected_count := (item->>'questionCount')::integer;

    if item->>'kind' = 'new_activity' then
      select * into v_activity
      from learning.activities
      where stable_key = item->>'activityKey';
      if found then
        if v_activity.id is distinct from (item->>'activityId')::uuid
           or v_activity.title is distinct from item->>'title'
           or v_activity.git_path is distinct from item->>'gitPath'
           or v_activity.active is not true then
          raise exception 'UNIT3_BATCH_A1_RECOVERY_CONFLICT: activity % exists with incompatible identity', item->>'activityKey';
        end if;
      end if;
    end if;

    select version.* into v_version
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = item->>'activityKey'
      and version.version = item->>'version';

    if not found then
      continue;
    end if;

    if v_version.id is distinct from (item->>'versionId')::uuid
       or v_version.content_hash is distinct from item->>'contentHash'
       or v_version.question_count is distinct from v_expected_count
       or v_version.max_score is distinct from (item->>'maxScore')::numeric
       or v_version.retired_at is not null then
      raise exception 'UNIT3_BATCH_A1_RECOVERY_CONFLICT: % % metadata is incompatible', item->>'activityKey', item->>'version';
    end if;

    select count(*)::integer into v_question_rows
    from learning.questions
    where activity_version_id = v_version.id;

    select count(*)::integer into v_attempts
    from learning.attempts
    where activity_version_id = v_version.id;

    select count(*)::integer into v_delivery
    from learning.activity_delivery
    where activity_version_id = v_version.id;

    select count(*)::integer into v_assignments
    from learning.activity_assignments
    where activity_version_id = v_version.id;

    select count(*)::integer into v_languages
    from learning.activity_version_languages
    where activity_version_id = v_version.id;

    if v_version.published_at is not null then
      perform learning.assert_unit3_batch_a1_questions_match(item, v_version.id);
    elsif v_question_rows = 0 then
      if coalesce((item->>'allowEmptyUnpublished')::boolean, false) is not true then
        raise exception 'UNIT3_BATCH_A1_RECOVERY_CONFLICT: unexpected empty unpublished version for % %', item->>'activityKey', item->>'version';
      end if;
      if v_attempts <> 0 or v_delivery <> 0 or v_assignments <> 0 or v_languages <> 0 then
        raise exception 'UNIT3_BATCH_A1_RECOVERY_CONFLICT: residue % % has unexpected dependents', item->>'activityKey', item->>'version';
      end if;
    else
      if v_attempts <> 0 then
        raise exception 'UNIT3_BATCH_A1_RECOVERY_CONFLICT: unpublished % % has learner attempts', item->>'activityKey', item->>'version';
      end if;
      perform learning.assert_unit3_batch_a1_questions_match(item, v_version.id);
    end if;
  end loop;

  for item in
    select value from jsonb_array_elements(catalogue)
  loop
    if item->>'kind' = 'new_activity' then
      insert into learning.activities (id, module_id, stable_key, title, activity_type, git_path, active)
      values (
        (item->>'activityId')::uuid,
        {module_sql},
        item->>'activityKey',
        item->>'title',
        'practice',
        item->>'gitPath',
        true
      )
      on conflict (stable_key) do nothing;
      v_activity_id := (item->>'activityId')::uuid;
    else
      select id into strict v_activity_id
      from learning.activities
      where stable_key = item->>'activityKey';
    end if;

    insert into learning.activity_versions (
      id, activity_id, version, content_hash, max_score, question_count, published_at
    )
    values (
      (item->>'versionId')::uuid,
      v_activity_id,
      item->>'version',
      item->>'contentHash',
      (item->>'maxScore')::numeric,
      (item->>'questionCount')::integer,
      null
    )
    on conflict (activity_id, version) do nothing;

    select * into strict v_version
    from learning.activity_versions
    where id = (item->>'versionId')::uuid;

    if v_version.published_at is null then
      for question in
        select value from jsonb_array_elements(item->'questions')
      loop
        insert into learning.questions (
          id, activity_version_id, stable_key, section_key, section_title, question_type, analytics_title, ordinal, max_score
        )
        values (
          (question->>'id')::uuid,
          v_version.id,
          question->>'stableKey',
          question->>'sectionKey',
          question->>'sectionTitle',
          question->>'questionType',
          question->>'analyticsTitle',
          (question->>'ordinal')::integer,
          (question->>'maxScore')::numeric
        )
        on conflict (activity_version_id, stable_key) do nothing;

        if question->'marking' is not null and question->'marking' <> 'null'::jsonb then
          insert into learning.question_marking (question_id, spec)
          values ((question->>'id')::uuid, question->'marking')
          on conflict (question_id) do nothing;
        end if;
      end loop;

      update learning.activity_versions
      set published_at = {sql_literal(PUBLISHED_AT)}::timestamptz
      where id = v_version.id
        and published_at is null;
    end if;

    v_week_id := case (item->>'weekNumber')::integer
      when 1 then {week1_sql}
      when 2 then {week2_sql}
      when 5 then {week5_sql}
      else null
    end;

    insert into learning.activity_delivery (
      activity_version_id, academic_year_id, curriculum_week_id, week_number, session_number, sort_order, active
    )
    select
      v_version.id,
      academic_year.id,
      v_week_id,
      (item->>'weekNumber')::integer,
      (item->>'sessionNumber')::integer,
      0,
      true
    from learning.academic_years as academic_year
    where academic_year.active
      and not exists (
        select 1
        from learning.activity_delivery as delivery
        where delivery.activity_version_id = v_version.id
          and delivery.academic_year_id = academic_year.id
          and delivery.group_id is null
      )
    order by academic_year.code
    limit 1;

    insert into learning.activity_assignments (id, group_id, activity_version_id, required, active)
    select
      (item->>'assignmentId')::uuid,
      learner_group.id,
      v_version.id,
      true,
      true
    from learning.groups as learner_group
    where learner_group.code = 'CYBER-TEST-A'
    on conflict (group_id, activity_version_id) do nothing;
  end loop;
end;
$recovery$;

create or replace function learning.assert_unit3_batch_a1_questions_match(item jsonb, version_id uuid)
returns void
language plpgsql
set search_path = ''
as $assert$
declare
  v_question_rows integer;
  v_matched_count integer;
  v_marking_count integer;
  v_expected_count integer;
begin
  v_expected_count := jsonb_array_length(item->'questions');

  select count(*)::integer into v_question_rows
  from learning.questions
  where activity_version_id = version_id;

  if v_question_rows <> v_expected_count then
    raise exception 'UNIT3_BATCH_A1_RECOVERY_CONFLICT: % % question row count is incompatible', item->>'activityKey', item->>'version';
  end if;

  select count(*)::integer into v_matched_count
  from jsonb_array_elements(item->'questions') as expected
  join learning.questions as question
    on question.id = (expected.value->>'id')::uuid
   and question.activity_version_id = version_id
   and question.stable_key = expected.value->>'stableKey'
   and question.section_key = expected.value->>'sectionKey'
   and question.section_title = expected.value->>'sectionTitle'
   and question.question_type = expected.value->>'questionType'
   and question.analytics_title = expected.value->>'analyticsTitle'
   and question.ordinal = (expected.value->>'ordinal')::integer
   and question.max_score = (expected.value->>'maxScore')::numeric;

  if v_matched_count <> v_expected_count then
    raise exception 'UNIT3_BATCH_A1_RECOVERY_CONFLICT: % % questions do not match the canonical catalogue', item->>'activityKey', item->>'version';
  end if;

  select count(*)::integer into v_marking_count
  from jsonb_array_elements(item->'questions') as expected
  left join learning.question_marking as marking
    on marking.question_id = (expected.value->>'id')::uuid
  where (
      jsonb_typeof(expected.value->'marking') = 'null'
      and marking.question_id is not null
    ) or (
      jsonb_typeof(expected.value->'marking') = 'object'
      and marking.spec is distinct from expected.value->'marking'
    );

  if v_marking_count <> 0 then
    raise exception 'UNIT3_BATCH_A1_RECOVERY_CONFLICT: % % marking specs are incompatible', item->>'activityKey', item->>'version';
  end if;
end;
$assert$;

revoke all on function learning.apply_unit3_batch_a1_recovery() from public;
revoke all on function learning.assert_unit3_batch_a1_questions_match(jsonb, uuid) from public;

select learning.apply_unit3_batch_a1_recovery();

commit;
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Unit 3 Batch A1 recovery SQL.")
    default_manifest = Path(__file__).resolve().parents[2] / "supabase/data/manifests/unit3-batch-a1"
    parser.add_argument("--manifest-dir", type=Path, default=default_manifest)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    sql = generate_recovery(args.manifest_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")
    print(f"Generated {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
