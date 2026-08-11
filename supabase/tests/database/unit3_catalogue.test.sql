begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(20);

select ok(exists(select 1 from learning.courses where stable_key = 'ocr-level-3-it'), 'OCR Level 3 IT course exists');
select ok(exists(select 1 from learning.modules m join learning.courses c on c.id = m.course_id where c.stable_key = 'ocr-level-3-it' and m.stable_key = 'unit-3-cyber-security'), 'Unit 3 module exists');
select is((select count(*)::int from learning.curriculum_weeks w join learning.modules m on m.id = w.module_id where m.stable_key = 'unit-3-cyber-security'), 7, 'Unit 3 has seven curriculum weeks');
select is((select count(*)::int from learning.activities a join learning.modules m on m.id = a.module_id where m.stable_key = 'unit-3-cyber-security'), 76, 'Unit 3 has 76 activities');
select ok(exists(select 1 from learning.activities where stable_key = 'week2-ocr-question-practice'), 'representative Week 2 activity exists');
select ok(exists(select 1 from learning.activities where stable_key = 'week7-testing-methods'), 'representative Week 7 activity exists');
select ok(not exists(select 1 from learning.activities where stable_key is null or title is null or git_path is null), 'activities have critical identifiers');
select is((select count(*)::int from learning.activities a join learning.modules m on m.id = a.module_id where m.stable_key = 'unit-3-cyber-security' and a.stable_key like 'u3-w01-%'), 8, 'Week 1 has eight activities');
select is((select count(*)::int from learning.activities a join learning.modules m on m.id = a.module_id join learning.activity_delivery d on d.activity_version_id in (select id from learning.activity_versions where activity_id=a.id) where m.stable_key = 'unit-3-cyber-security' and d.week_number = 2), 11, 'Week 2 has eleven activities');
select is((select count(*)::int from learning.activities a join learning.modules m on m.id = a.module_id join learning.activity_delivery d on d.activity_version_id in (select id from learning.activity_versions where activity_id=a.id) where m.stable_key = 'unit-3-cyber-security' and d.week_number = 3), 7, 'Week 3 has seven activities');
select is((select count(*)::int from learning.activities a join learning.modules m on m.id = a.module_id join learning.activity_delivery d on d.activity_version_id in (select id from learning.activity_versions where activity_id=a.id) where m.stable_key = 'unit-3-cyber-security' and d.week_number = 4), 10, 'Week 4 has ten activities');
select is((select count(*)::int from learning.activities a join learning.modules m on m.id = a.module_id join learning.activity_delivery d on d.activity_version_id in (select id from learning.activity_versions where activity_id=a.id) where m.stable_key = 'unit-3-cyber-security' and d.week_number = 5), 10, 'Week 5 has ten activities');
select is((select count(*)::int from learning.activities a join learning.modules m on m.id = a.module_id join learning.activity_delivery d on d.activity_version_id in (select id from learning.activity_versions where activity_id=a.id) where m.stable_key = 'unit-3-cyber-security' and d.week_number = 6), 18, 'Week 6 has eighteen activities');
select is((select count(*)::int from learning.activities a join learning.modules m on m.id = a.module_id join learning.activity_delivery d on d.activity_version_id in (select id from learning.activity_versions where activity_id=a.id) where m.stable_key = 'unit-3-cyber-security' and d.week_number = 7), 12, 'Week 7 has twelve activities');
select ok((select relrowsecurity from pg_class where oid = 'learning.activities'::regclass), 'learning activities remain RLS protected');
select is((select count(*)::int from learning.questions q join learning.activity_versions v on v.id = q.activity_version_id join learning.activities a on a.id = v.activity_id join learning.modules m on m.id = a.module_id where m.stable_key = 'unit-3-cyber-security'), 472, 'Unit 3 has 472 importable grounded question records');
select ok(exists(select 1 from learning.questions where stable_key = 'MW-Q1'), 'representative question ID exists');
select ok(not exists(select 1 from learning.questions group by activity_version_id, stable_key having count(*) > 1), 'question IDs are unique within activity versions');
select ok((select count(distinct stable_key) from learning.questions) < (select count(*) from learning.questions), 'duplicate textual IDs across activities are allowed');
select ok(not exists(select 1 from learning.questions q join learning.activity_versions v on v.id = q.activity_version_id join learning.activities a on a.id = v.activity_id where a.stable_key like 'week%' and q.max_score <= 0), 'question maxima are positive and grounded');

select * from finish();
rollback;
