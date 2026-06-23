-- Stampee upgrade script: add get_active_venue_claim, used by the venue page
-- to detect an already-pending discount claim instead of generating a new
-- PIN and allowing duplicate submissions on refresh.
-- New projects should use migration.sql instead.

create or replace function public.get_active_venue_claim(campaign_id_input text)
returns jsonb as $$
declare
  claim_row record;
begin
  select t.id, t.pin
  into claim_row
  from public.transactions t
  where t.campaign_id = campaign_id_input
    and t.customer_id = (select auth.uid())
    and t.type = 'discount_claim'
    and t.status = 'pending'
  order by t."timestamp" desc
  limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object('id', claim_row.id, 'pin', claim_row.pin);
end;
$$ language plpgsql security definer
set search_path = public;

grant execute on function public.get_active_venue_claim(text) to authenticated;
