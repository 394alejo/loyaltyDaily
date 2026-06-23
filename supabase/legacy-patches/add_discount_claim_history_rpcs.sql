-- Stampee upgrade script: add discount-claim history reporting for
-- customers ("My Visits") and staff/owners ("Transaction History").
-- New projects should use migration.sql instead.

-- History must survive a venue later deleting a campaign. campaign_id is
-- ON DELETE SET NULL, which also wipes out the only path to a claim's
-- owner_id (campaigns.owner_id) — so once a campaign is gone, a staff/owner
-- history query would have no safe way to scope rows to "their" venue.
-- We snapshot owner_id directly onto the transaction row at insert time
-- (mirrors how issued_cards.template_snapshot survives campaign deletion),
-- so ownership scoping never depends on a live campaign row.
alter table public.transactions
  add column if not exists owner_id uuid references public.profiles(id) on delete set null;

create or replace function public.set_discount_claim_owner()
returns trigger as $$
begin
  if new.type = 'discount_claim' and new.campaign_id is not null then
    select owner_id into new.owner_id from public.campaigns where id = new.campaign_id;
  end if;
  return new;
end;
$$ language plpgsql security definer
set search_path = public;

drop trigger if exists transactions_set_discount_claim_owner on public.transactions;
create trigger transactions_set_discount_claim_owner
  before insert on public.transactions
  for each row execute function public.set_discount_claim_owner();

-- Backfill owner_id for any discount_claim rows inserted before this column
-- existed, as long as their campaign hasn't been deleted yet.
update public.transactions t
set owner_id = c.owner_id
from public.campaigns c
where t.campaign_id = c.id
  and t.type = 'discount_claim'
  and t.owner_id is null;

create or replace function public.get_my_discount_claims()
returns jsonb as $$
begin
  return coalesce(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'venueName', coalesce(p.business_name, 'Deleted campaign'),
      'campaignName', coalesce(c.name, 'Deleted campaign'),
      'discountPercent', c.user_discount_percent,
      'status', t.status,
      'timestamp', t."timestamp"
    ) order by t."timestamp" desc
  ), '[]'::jsonb)
  from public.transactions t
  left join public.campaigns c on c.id = t.campaign_id
  left join public.profiles p on p.id = t.owner_id
  where t.customer_id = (select auth.uid())
    and t.type = 'discount_claim'
    and t.status in ('confirmed', 'rejected')
  limit 300;
end;
$$ language plpgsql security definer
set search_path = public;

grant execute on function public.get_my_discount_claims() to authenticated;

create or replace function public.get_discount_claim_history()
returns jsonb as $$
declare
  caller_role text;
  effective_owner_id uuid;
begin
  select role, coalesce(owner_id, id) into caller_role, effective_owner_id
  from public.profiles
  where id = (select auth.uid());

  if caller_role is null or caller_role not in ('owner', 'staff') then
    return '[]'::jsonb;
  end if;

  return coalesce(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'campaignName', coalesce(c.name, 'Deleted campaign'),
      'customerName', p.full_name,
      'pin', t.pin,
      'discountPercent', c.user_discount_percent,
      'status', t.status,
      'timestamp', t."timestamp"
    ) order by t."timestamp" desc
  ), '[]'::jsonb)
  from public.transactions t
  left join public.campaigns c on c.id = t.campaign_id
  left join public.profiles p on p.id = t.customer_id
  where t.type = 'discount_claim'
    and t.status in ('confirmed', 'rejected')
    and t.owner_id = effective_owner_id
  limit 300;
end;
$$ language plpgsql security definer
set search_path = public;

grant execute on function public.get_discount_claim_history() to authenticated;
