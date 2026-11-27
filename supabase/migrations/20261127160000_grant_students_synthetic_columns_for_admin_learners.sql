-- admin_api.learners is security_invoker and projects is_synthetic /
-- synthetic_purpose. Those columns were added later; authenticated only had
-- the original column-level SELECT list, so platform_admin reads failed with
-- "permission denied for table students" even though RLS already allows
-- platform_admin. Grant the missing synthetic columns only (least privilege).

grant select (is_synthetic, synthetic_purpose) on learning.students to authenticated;

comment on view admin_api.learners is
  'Staff learner directory for platform_admin. security_invoker; requires column SELECT on learning.students including is_synthetic/synthetic_purpose, gated by RLS + view predicate.';
