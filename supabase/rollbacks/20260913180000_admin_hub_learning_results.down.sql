-- Review-only rollback. Do not apply against hosted production.
-- Drops the additive hub-learning Results RPCs. Learner records are untouched.

drop function if exists admin_api.list_hub_learning_result_evidence(text, text, uuid);
drop function if exists admin_api.summarise_hub_learning_results(text, text, text, text, integer, integer, text, text);
drop function if exists admin_api.list_hub_learning_results(text, text, text, text, integer, integer, text, text, integer);
drop function if exists learning.staff_hub_learning_result_rows(text, text, text, text, integer, integer, text, text);
drop function if exists admin_api.list_hub_learning_result_filters(text);
drop function if exists learning.staff_visible_hub_group_ids(text);
drop function if exists learning.staff_can_read_hub_results(text);
