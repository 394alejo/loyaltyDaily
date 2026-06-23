-- Stampee upgrade script: add the customer role, venue discount split
-- columns, and the reverse-scan discount claim flow to existing projects.
-- New projects should use migration.sql instead.

-- 1. Customer role + full name on profiles
alter table public.profiles
  add column if not exists full_name text;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('owner', 'staff', 'customer'));

create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_role text;
  v_owner_id uuid;
begin
  v_role := coalesce(new.raw_user_meta_data->>'role', 'owner');

  if v_role = 'staff'
    and (new.raw_user_meta_data->>'owner_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  then
    v_owner_id := (new.raw_user_meta_data->>'owner_id')::uuid;
  else
    v_owner_id := null;
  end if;

  insert into public.profiles (id, business_name, full_name, email, slug, role, owner_id, status, access, tier)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'business_name', ''),
    new.raw_user_meta_data->>'full_name',
    new.email,
    case when v_role = 'owner' then new.raw_user_meta_data->>'slug' else null end,
    v_role,
    v_owner_id,
    'unverified',
    'active',
    'free'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer
set search_path = public;

-- 2. Venue discount split on campaigns
alter table public.campaigns
  add column if not exists total_discount_percent numeric(5,2) not null default 0;

alter table public.campaigns
  add column if not exists ngo_commission_percent numeric(5,2) not null default 0;

alter table public.campaigns
  add column if not exists user_discount_percent numeric(5,2) generated always as (total_discount_percent - ngo_commission_percent) stored;

alter table public.campaigns drop constraint if exists campaigns_discount_range_check;
alter table public.campaigns add constraint campaigns_discount_range_check
  check (
    ngo_commission_percent >= 0
    and total_discount_percent >= 0
    and total_discount_percent <= 100
    and ngo_commission_percent <= total_discount_percent
  );

-- 3. Discount claim transactions (no issued_cards record involved)
alter table public.transactions alter column card_id drop not null;

alter table public.transactions
  add column if not exists campaign_id text references public.campaigns(id) on delete set null;

alter table public.transactions
  add column if not exists customer_id uuid references public.profiles(id) on delete set null;

alter table public.transactions
  add column if not exists pin text;

alter table public.transactions
  add column if not exists status text not null default 'pending';

alter table public.transactions drop constraint if exists transactions_status_check;
alter table public.transactions add constraint transactions_status_check
  check (status in ('pending', 'confirmed', 'rejected'));

alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check
  check (type in ('stamp_add', 'stamp_remove', 'redeem', 'issued', 'discount_claim'));

drop policy if exists "Customers can insert own discount claims" on public.transactions;
create policy "Customers can insert own discount claims"
  on public.transactions for insert
  with check (
    type = 'discount_claim'
    and customer_id = (select auth.uid())
  );

-- 4. Public-safe venue lookup for the reverse-scan flow
create or replace function public.get_venue_campaign(campaign_id_input text)
returns jsonb as $$
declare
  campaign_row record;
begin
  select c.id, c.name, c.is_enabled, c.user_discount_percent, p.business_name
  into campaign_row
  from public.campaigns c
  join public.profiles p on p.id = c.owner_id
  where c.id = campaign_id_input;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'id', campaign_row.id,
    'name', campaign_row.name,
    'isEnabled', campaign_row.is_enabled,
    'businessName', campaign_row.business_name,
    'userDiscountPercent', campaign_row.user_discount_percent
  );
end;
$$ language plpgsql security definer
set search_path = public;

grant execute on function public.get_venue_campaign(text) to authenticated;

-- 5. Staff/owner cashier queue for the reverse-scan discount flow.
create or replace function public.get_pending_discount_claims()
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
      'campaignId', t.campaign_id,
      'campaignName', c.name,
      'customerName', p.full_name,
      'pin', t.pin,
      'discountPercent', c.user_discount_percent,
      'timestamp', t."timestamp"
    ) order by t."timestamp"
  ), '[]'::jsonb)
  from public.transactions t
  join public.campaigns c on c.id = t.campaign_id
  left join public.profiles p on p.id = t.customer_id
  where t.status = 'pending'
    and t.type = 'discount_claim'
    and c.owner_id = effective_owner_id;
end;
$$ language plpgsql security definer
set search_path = public;

grant execute on function public.get_pending_discount_claims() to authenticated;

create or replace function public.set_discount_claim_status(transaction_id_input text, new_status text)
returns jsonb as $$
declare
  caller_role text;
  effective_owner_id uuid;
  updated_id text;
begin
  if new_status not in ('confirmed', 'rejected') then
    return jsonb_build_object('success', false);
  end if;

  select role, coalesce(owner_id, id) into caller_role, effective_owner_id
  from public.profiles
  where id = (select auth.uid());

  if caller_role is null or caller_role not in ('owner', 'staff') then
    return jsonb_build_object('success', false);
  end if;

  update public.transactions t
  set status = new_status
  from public.campaigns c
  where t.id = transaction_id_input
    and t.campaign_id = c.id
    and c.owner_id = effective_owner_id
    and t.status = 'pending'
    and t.type = 'discount_claim'
  returning t.id into updated_id;

  if updated_id is null then
    return jsonb_build_object('success', false);
  end if;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer
set search_path = public;

grant execute on function public.set_discount_claim_status(text, text) to authenticated;
