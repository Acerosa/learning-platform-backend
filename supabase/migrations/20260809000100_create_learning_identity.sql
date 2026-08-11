create extension if not exists pgcrypto with schema extensions;

create schema if not exists learning;
create schema if not exists api;

revoke all on schema learning from public, anon, authenticated;
revoke all on schema api from public, anon, authenticated;

create table learning.academic_years (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  starts_on date not null,
  ends_on date not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint academic_year_dates_valid check (ends_on >= starts_on)
);

create table learning.courses (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  code text,
  title text not null,
  qualification_level text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_stable_key_valid check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

create unique index courses_code_unique
  on learning.courses (code)
  where code is not null;

create table learning.groups (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null
    references learning.academic_years (id) on delete restrict,
  course_id uuid not null
    references learning.courses (id) on delete restrict,
  code text not null,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint groups_year_course_code_unique
    unique (academic_year_id, course_id, code)
);

create index groups_course_year_idx
  on learning.groups (course_id, academic_year_id);

create table learning.students (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid
    references auth.users (id) on delete set null,
  student_number text not null unique,
  first_name text not null,
  surname text,
  display_name text not null,
  contact_email text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_number_not_blank check (btrim(student_number) <> ''),
  constraint student_first_name_not_blank check (btrim(first_name) <> ''),
  constraint student_display_name_not_blank check (btrim(display_name) <> '')
);

create unique index students_auth_user_unique
  on learning.students (auth_user_id)
  where auth_user_id is not null;

create index students_active_idx
  on learning.students (active, student_number);

create table learning.teachers (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid
    references auth.users (id) on delete set null,
  staff_reference text,
  display_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint teacher_display_name_not_blank check (btrim(display_name) <> '')
);

create unique index teachers_auth_user_unique
  on learning.teachers (auth_user_id)
  where auth_user_id is not null;

create unique index teachers_staff_reference_unique
  on learning.teachers (staff_reference)
  where staff_reference is not null;

create table learning.enrolments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null
    references learning.students (id) on delete restrict,
  group_id uuid not null
    references learning.groups (id) on delete restrict,
  joined_on date not null,
  left_on date,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint enrolment_status_valid
    check (status in ('active', 'completed', 'withdrawn')),
  constraint enrolment_dates_valid
    check (left_on is null or left_on >= joined_on),
  constraint enrolment_history_unique
    unique (student_id, group_id, joined_on)
);

create unique index enrolments_one_active_per_student
  on learning.enrolments (student_id)
  where status = 'active';

create index enrolments_group_status_idx
  on learning.enrolments (group_id, status);

create index enrolments_student_status_idx
  on learning.enrolments (student_id, status);

create table learning.teacher_group_access (
  teacher_id uuid not null
    references learning.teachers (id) on delete restrict,
  group_id uuid not null
    references learning.groups (id) on delete restrict,
  role text not null default 'teacher',
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (teacher_id, group_id),
  constraint teacher_group_role_valid
    check (role in ('teacher', 'lead', 'viewer')),
  constraint teacher_group_access_dates_valid
    check (revoked_at is null or revoked_at >= granted_at)
);

create index teacher_group_access_group_idx
  on learning.teacher_group_access (group_id, revoked_at);

create index teacher_group_access_teacher_idx
  on learning.teacher_group_access (teacher_id, revoked_at);
