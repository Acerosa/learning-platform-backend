create view api.my_activity_delivery
with (security_invoker = true)
as
select
  delivery.id,
  activity.stable_key as activity_key,
  version.version as activity_version,
  module.stable_key as module_key,
  delivery.week_number,
  delivery.session_number,
  delivery.sort_order,
  delivery.available_from,
  delivery.available_until
from learning.activity_delivery delivery
join learning.activity_versions version
  on version.id = delivery.activity_version_id
join learning.activities activity
  on activity.id = version.activity_id
join learning.modules module
  on module.id = activity.module_id
where delivery.active = true;

grant select on api.my_activity_delivery to authenticated;
