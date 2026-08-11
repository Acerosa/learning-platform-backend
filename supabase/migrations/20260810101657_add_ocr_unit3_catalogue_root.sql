insert into learning.courses (
  id,
  stable_key,
  code,
  title,
  qualification_level,
  active
)
values (
  'c3000000-0000-4000-8000-000000000001',
  'ocr-level-3-it',
  'OCR-L3-IT',
  'OCR Level 3 IT',
  'Level 3',
  true
)
on conflict (stable_key) do nothing;

insert into learning.modules (
  id,
  course_id,
  stable_key,
  title,
  sort_order,
  active
)
values (
  'c3100000-0000-4000-8000-000000000001',
  'c3000000-0000-4000-8000-000000000001',
  'unit-3-cyber-security',
  'Unit 3 Cyber Security',
  3,
  true
)
on conflict (course_id, stable_key) do nothing;
