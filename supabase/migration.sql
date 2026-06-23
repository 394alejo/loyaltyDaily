-- ============================================================
-- Stampee: Full Database Schema (Idempotent)
-- Canonical fresh-install script for new Supabase projects.
-- Safe to re-run in Supabase SQL Editor.
-- For existing or older projects, use the targeted upgrade/repair
-- scripts in legacy-patches/ only when needed.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- 1. PROFILES TABLE
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  business_name text not null,
  full_name text,
  email text not null,
  slug text unique,
  role text not null default 'owner' check (role in ('owner', 'staff', 'customer', 'admin')),
  owner_id uuid references public.profiles(id) on delete cascade,
  status text not null default 'unverified' check (status in ('unverified', 'verified')),
  access text not null default 'active' check (access in ('active', 'disabled')),
  tier text not null default 'free' check (tier in ('free', 'pro')),
  tier_expires_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists full_name text;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('owner', 'staff', 'customer', 'admin'));

alter table public.profiles enable row level security;

create or replace function public.current_staff_owner_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select p.owner_id
  from public.profiles p
  where p.id = (select auth.uid())
    and p.role = 'staff'
  limit 1
$$;

-- Stampee-operator role, manually provisioned (no self-serve signup). Used
-- to gate the platform-wide "award points" tool without a broad profiles
-- read policy that would expose every customer to every other role.
create or replace function public.current_user_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from public.profiles where id = (select auth.uid())
$$;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
  on public.profiles for select
  using ((select auth.uid()) = id);

drop policy if exists "Owners can read own staff profiles" on public.profiles;
create policy "Owners can read own staff profiles"
  on public.profiles for select
  using (
    role = 'staff' and owner_id = (select auth.uid())
  );

drop policy if exists "Staff can read owner profile" on public.profiles;
create policy "Staff can read owner profile"
  on public.profiles for select
  using (
    id = (select public.current_staff_owner_id())
  );

drop policy if exists "Admins can read customer profiles" on public.profiles;
create policy "Admins can read customer profiles"
  on public.profiles for select
  using (
    role = 'customer' and (select public.current_user_role()) = 'admin'
  );

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update
  using ((select auth.uid()) = id);

drop policy if exists "Owners can update own staff profiles" on public.profiles;
create policy "Owners can update own staff profiles"
  on public.profiles for update
  using (
    role = 'staff' and owner_id = (select auth.uid())
  );

drop policy if exists "Owners can insert staff profiles" on public.profiles;
create policy "Owners can insert staff profiles"
  on public.profiles for insert
  with check (
    role = 'staff' AND owner_id = (select auth.uid())
  );

drop policy if exists "Allow trigger insert for new signups" on public.profiles;
create policy "Allow trigger insert for new signups"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Auto-create profile on signup
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- 2. CAMPAIGNS TABLE
create table if not exists public.campaigns (
  id text primary key default gen_random_uuid()::text,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  is_enabled boolean not null default true,
  description text not null default '',
  reward_name text not null default '',
  tagline text,
  background_image text,
  background_opacity int default 100,
  logo_image text,
  show_logo boolean default true,
  title_size text,
  icon_key text not null default 'Coffee',
  colors jsonb not null,
  total_stamps int not null default 10,
  social jsonb,
  total_discount_percent numeric(5,2) not null default 0,
  ngo_commission_percent numeric(5,2) not null default 0,
  user_discount_percent numeric(5,2) generated always as (total_discount_percent - ngo_commission_percent) stored,
  created_at timestamptz not null default now()
);

alter table public.campaigns
  add column if not exists is_enabled boolean not null default true;

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

alter table public.campaigns enable row level security;

drop policy if exists "Owners can manage own campaigns" on public.campaigns;
create policy "Owners can manage own campaigns"
  on public.campaigns for all
  using ((select auth.uid()) = owner_id);

drop policy if exists "Staff can read owner campaigns" on public.campaigns;
create policy "Staff can read owner campaigns"
  on public.campaigns for select
  using (
    owner_id = (select owner_id from public.profiles where id = auth.uid())
  );


-- 3. CUSTOMERS TABLE
create table if not exists public.customers (
  id text primary key default gen_random_uuid()::text,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  email text not null,
  mobile text,
  status text not null default 'Active' check (status in ('Active', 'Inactive')),
  created_at timestamptz not null default now()
);

alter table public.customers enable row level security;

drop policy if exists "Owners can manage own customers" on public.customers;
create policy "Owners can manage own customers"
  on public.customers for all
  using (auth.uid() = owner_id);

drop policy if exists "Staff can read owner customers" on public.customers;
create policy "Staff can read owner customers"
  on public.customers for select
  using (
    owner_id = (select owner_id from public.profiles where id = auth.uid())
  );

drop policy if exists "Staff can update owner customers" on public.customers;
create policy "Staff can update owner customers"
  on public.customers for update
  using (
    owner_id = (select owner_id from public.profiles where id = auth.uid())
  );


-- 4. ISSUED CARDS TABLE
create table if not exists public.issued_cards (
  id text primary key default gen_random_uuid()::text,
  unique_id uuid not null default gen_random_uuid() unique,
  customer_id text not null references public.customers(id) on delete cascade,
  campaign_id text references public.campaigns(id) on delete set null,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  campaign_name text not null,
  stamps int not null default 0,
  last_visit date not null default current_date,
  status text not null default 'Active' check (status in ('Active', 'Redeemed')),
  completed_date date,
  template_snapshot jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.prevent_issuing_disabled_campaign_card()
returns trigger as $$
declare
  campaign_enabled boolean;
begin
  if new.campaign_id is null then
    return new;
  end if;

  select c.is_enabled
  into campaign_enabled
  from public.campaigns c
  where c.id = new.campaign_id;

  if found and campaign_enabled = false then
    raise exception 'CAMPAIGN_DISABLED: This campaign is disabled and cannot issue new cards.';
  end if;

  return new;
end;
$$ language plpgsql
set search_path = public;

drop trigger if exists issued_cards_block_disabled_campaign on public.issued_cards;
create trigger issued_cards_block_disabled_campaign
  before insert on public.issued_cards
  for each row
  execute function public.prevent_issuing_disabled_campaign_card();

update public.issued_cards ic
set template_snapshot = coalesce(
      ic.template_snapshot,
      jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'description', c.description,
        'rewardName', c.reward_name,
        'tagline', c.tagline,
        'backgroundImage', c.background_image,
        'backgroundOpacity', c.background_opacity,
        'logoImage', c.logo_image,
        'showLogo', c.show_logo,
        'titleSize', c.title_size,
        'iconKey', c.icon_key,
        'colors', c.colors,
        'totalStamps', c.total_stamps,
        'social', c.social
      )
    ),
    campaign_name = coalesce(nullif(ic.campaign_name, ''), c.name)
from public.campaigns c
where ic.campaign_id = c.id
  and (ic.template_snapshot is null or nullif(ic.campaign_name, '') is null);

do $$
declare
  issued_cards_campaign_fk text;
begin
  select conname
  into issued_cards_campaign_fk
  from pg_constraint
  where conrelid = 'public.issued_cards'::regclass
    and contype = 'f'
    and confrelid = 'public.campaigns'::regclass
    and array_position(
      conkey,
      (
        select attnum
        from pg_attribute
        where attrelid = 'public.issued_cards'::regclass
          and attname = 'campaign_id'
      )
    ) is not null
  limit 1;

  if issued_cards_campaign_fk is not null then
    execute format(
      'alter table public.issued_cards drop constraint %I',
      issued_cards_campaign_fk
    );
  end if;
end;
$$;

alter table public.issued_cards
  alter column campaign_id drop not null;

alter table public.issued_cards
  add constraint issued_cards_campaign_id_fkey
  foreign key (campaign_id)
  references public.campaigns(id)
  on delete set null;

alter table public.issued_cards enable row level security;

drop policy if exists "Owners can manage own issued cards" on public.issued_cards;
create policy "Owners can manage own issued cards"
  on public.issued_cards for all
  using (auth.uid() = owner_id);

drop policy if exists "Staff can read owner issued cards" on public.issued_cards;
create policy "Staff can read owner issued cards"
  on public.issued_cards for select
  using (
    owner_id = (select owner_id from public.profiles where id = auth.uid())
  );

drop policy if exists "Staff can update owner issued cards" on public.issued_cards;
create policy "Staff can update owner issued cards"
  on public.issued_cards for update
  using (
    owner_id = (select owner_id from public.profiles where id = auth.uid())
  );

-- Public card access is handled only via security definer RPCs.
drop policy if exists "Anyone can read issued cards by unique_id" on public.issued_cards;


-- 5. TRANSACTIONS TABLE
create table if not exists public.transactions (
  id text primary key default gen_random_uuid()::text,
  card_id text references public.issued_cards(id) on delete cascade,
  campaign_id text references public.campaigns(id) on delete set null,
  customer_id uuid references public.profiles(id) on delete set null,
  pin text,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  type text not null check (type in ('stamp_add', 'stamp_remove', 'redeem', 'issued', 'discount_claim')),
  amount int not null default 0,
  date text not null,
  "timestamp" bigint not null,
  title text not null,
  remarks text,
  actor_id uuid,
  actor_name text,
  actor_role text
);

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

alter table public.transactions enable row level security;

drop policy if exists "Customers can insert own discount claims" on public.transactions;
create policy "Customers can insert own discount claims"
  on public.transactions for insert
  with check (
    type = 'discount_claim'
    and customer_id = (select auth.uid())
  );

drop policy if exists "Owners can manage transactions for own cards" on public.transactions;
create policy "Owners can manage transactions for own cards"
  on public.transactions for all
  using (
    card_id in (select id from public.issued_cards where owner_id = (select auth.uid()))
  );

drop policy if exists "Staff can read owner transactions" on public.transactions;
create policy "Staff can read owner transactions"
  on public.transactions for select
  using (
    card_id in (
      select ic.id from public.issued_cards ic
      where ic.owner_id = (
        select owner_id from public.profiles where id = (select auth.uid())
      )
    )
  );

drop policy if exists "Staff can insert transactions for owner cards" on public.transactions;
create policy "Staff can insert transactions for owner cards"
  on public.transactions for insert
  with check (
    card_id in (
      select ic.id from public.issued_cards ic
      where ic.owner_id = (
        select owner_id from public.profiles where id = (select auth.uid())
      )
    )
  );

-- Public card history is exposed only through get_public_card().
drop policy if exists "Anyone can read transactions for public cards" on public.transactions;

-- Venue lookup for the reverse-scan flow. Returns only the customer-safe
-- subset of a campaign (never total_discount_percent or ngo_commission_percent).
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

-- Returns the calling customer's own pending discount claim for a venue, if
-- any, so the venue page can show the existing PIN instead of generating a
-- new one and re-submitting a duplicate row.
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


-- 6. LICENSE KEYS TABLE
create table if not exists public.license_keys (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  license_key text not null unique,
  platform text not null default 'gumroad',
  status text not null default 'active' check (status in ('active', 'expired', 'revoked')),
  activated_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.license_keys enable row level security;

drop policy if exists "Users can read own license keys" on public.license_keys;
create policy "Users can read own license keys"
  on public.license_keys for select
  using (profile_id = (select auth.uid()));

-- License activation is handled through activate_license_key().
drop policy if exists "Users can read unclaimed keys by key value" on public.license_keys;

drop policy if exists "Users can claim a license key" on public.license_keys;
create policy "Users can claim a license key"
  on public.license_keys for update
  using (profile_id is null OR profile_id = auth.uid());


-- 7. PUBLIC ACCESS HELPERS
-- Public access is handled through security definer RPCs instead of table-wide read policies.
drop policy if exists "Anyone can read profiles by slug" on public.profiles;

drop policy if exists "Anyone can read campaigns" on public.campaigns;

drop policy if exists "Anyone can read customers" on public.customers;

-- 7A. CAMPAIGN ASSET STORAGE (PUBLIC BUCKET + OBJECT POLICIES)
insert into storage.buckets (id, name, public)
values ('campaign-assets', 'campaign-assets', true)
on conflict (id) do update
set public = excluded.public;

drop policy if exists "Campaign assets are publicly readable" on storage.objects;
create policy "Campaign assets are publicly readable"
  on storage.objects for select
  using (bucket_id = 'campaign-assets');

drop policy if exists "Users can upload own campaign assets" on storage.objects;
create policy "Users can upload own campaign assets"
  on storage.objects for insert
  with check (
    bucket_id = 'campaign-assets'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can update own campaign assets" on storage.objects;
create policy "Users can update own campaign assets"
  on storage.objects for update
  using (
    bucket_id = 'campaign-assets'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'campaign-assets'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can delete own campaign assets" on storage.objects;
create policy "Users can delete own campaign assets"
  on storage.objects for delete
  using (
    bucket_id = 'campaign-assets'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );


-- 8. ACTIVATE LICENSE KEY FUNCTION (RPC)
create or replace function public.activate_license_key(key_input text)
returns jsonb as $$
declare
  key_row public.license_keys%rowtype;
  one_year_later timestamptz;
begin
  select * into key_row
  from public.license_keys
  where license_key = key_input
    and status = 'active'
    and profile_id is null
  for update;

  if not found then
    return jsonb_build_object('success', false, 'error', 'Invalid or already used license key');
  end if;

  one_year_later := now() + interval '1 year';

  update public.license_keys
  set profile_id = auth.uid(),
      activated_at = now(),
      expires_at = one_year_later
  where id = key_row.id;

  update public.profiles
  set tier = 'pro',
      tier_expires_at = one_year_later
  where id = auth.uid();

  return jsonb_build_object('success', true, 'expires_at', one_year_later);
end;
$$ language plpgsql security definer
set search_path = public;

create or replace function public.get_scan_entry_context(slug_input text, card_unique_id uuid)
returns jsonb as $$
declare
  owner_row record;
  card_row record;
begin
  select id, slug, business_name into owner_row
  from public.profiles
  where slug = slug_input and role = 'owner';
  if not found then return null; end if;

  select unique_id into card_row
  from public.issued_cards
  where unique_id = card_unique_id and owner_id = owner_row.id;
  if not found then return null; end if;

  return jsonb_build_object(
    'owner', jsonb_build_object(
      'id', owner_row.id,
      'slug', owner_row.slug,
      'businessName', owner_row.business_name
    ),
    'card', jsonb_build_object(
      'uniqueId', card_row.unique_id
    )
  );
end;
$$ language plpgsql security definer
set search_path = public;

create or replace function public.inspect_scanned_card(card_unique_id uuid)
returns jsonb as $$
declare
  actor_row record;
  card_row record;
  actor_owner_id uuid;
begin
  select id, role, owner_id into actor_row
  from public.profiles
  where id = auth.uid();
  if not found then
    return jsonb_build_object('status', 'missing');
  end if;

  actor_owner_id := case
    when actor_row.role = 'owner' then actor_row.id
    else actor_row.owner_id
  end;

  if actor_owner_id is null then
    return jsonb_build_object('status', 'missing');
  end if;

  select owner_id into card_row
  from public.issued_cards
  where unique_id = card_unique_id;

  if not found then
    return jsonb_build_object('status', 'missing');
  end if;

  if card_row.owner_id <> actor_owner_id then
    return jsonb_build_object('status', 'foreign');
  end if;

  return jsonb_build_object('status', 'owned');
end;
$$ language plpgsql security definer
set search_path = public;


-- 9. CREATE STAFF ACCOUNT (RPC)
create or replace function public.create_staff_account(
  staff_email text,
  staff_pin text,
  staff_name text
)
returns uuid as $$
declare
  new_uid uuid := gen_random_uuid();
  owner_uid uuid := auth.uid();
begin
  if not exists (
    select 1 from public.profiles where id = owner_uid and role = 'owner'
  ) then
    raise exception 'Only owners can create staff accounts';
  end if;

  if exists (select 1 from auth.users where email = lower(trim(staff_email))) then
    raise exception 'Email already in use';
  end if;

  if length(staff_pin) < 4 or length(staff_pin) > 6 then
    raise exception 'PIN must be 4-6 digits';
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, raw_app_meta_data,
    created_at, updated_at, is_sso_user
  ) values (
    new_uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    lower(trim(staff_email)),
    crypt(staff_pin, gen_salt('bf')),
    now(),
    jsonb_build_object('role', 'staff', 'owner_id', owner_uid::text, 'business_name', staff_name),
    jsonb_build_object('provider', 'email', 'providers', array_to_json(array['email'])),
    now(),
    now(),
    false
  );

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  ) values (
    new_uid,
    new_uid,
    jsonb_build_object('sub', new_uid::text, 'email', lower(trim(staff_email))),
    'email',
    new_uid::text,
    now(),
    now(),
    now()
  );

  return new_uid;
end;
$$ language plpgsql security definer
set search_path = public;


-- 10. UPDATE STAFF PIN (RPC)
create or replace function public.update_staff_pin(staff_id uuid, new_pin text)
returns void as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = staff_id and role = 'staff' and owner_id = auth.uid()
  ) then
    raise exception 'Not your staff member';
  end if;

  update auth.users
  set encrypted_password = crypt(new_pin, gen_salt('bf')),
      updated_at = now()
  where id = staff_id;
end;
$$ language plpgsql security definer
set search_path = public;


-- 11. DELETE STAFF ACCOUNT (RPC)
create or replace function public.delete_staff_account(staff_id uuid)
returns void as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = staff_id and role = 'staff' and owner_id = auth.uid()
  ) then
    raise exception 'Not your staff member';
  end if;

  delete from auth.users
  where id = staff_id;
end;
$$ language plpgsql security definer
set search_path = public;


-- 12. DELETE OWN ACCOUNT (RPC)
create or replace function public.delete_own_account()
returns void as $$
declare
  uid uuid := auth.uid();
begin
  delete from auth.users where id in (
    select id from public.profiles where owner_id = uid and role = 'staff'
  );
  delete from auth.users where id = uid;
end;
$$ language plpgsql security definer
set search_path = public;


-- 13. CHECK SLUG AVAILABILITY (RPC)
create or replace function public.is_slug_available(slug_input text)
returns boolean as $$
begin
  return not exists (
    select 1 from public.profiles
    where slug = lower(trim(slug_input))
    and role = 'owner'
  );
end;
$$ language plpgsql security definer
set search_path = public;

create or replace function public.get_public_campaign_signup_context(slug_input text, campaign_id_input text)
returns jsonb as $$
declare
  owner_row record;
  campaign_row record;
begin
  select id, slug, business_name
  into owner_row
  from public.profiles
  where slug = slug_input and role = 'owner';
  if not found then return null; end if;

  select id, name, is_enabled
  into campaign_row
  from public.campaigns
  where id = campaign_id_input
    and owner_id = owner_row.id;
  if not found then return null; end if;

  return jsonb_build_object(
    'owner', jsonb_build_object(
      'id', owner_row.id,
      'slug', owner_row.slug,
      'businessName', owner_row.business_name
    ),
    'campaign', jsonb_build_object(
      'id', campaign_row.id,
      'name', campaign_row.name,
      'isEnabled', campaign_row.is_enabled
    )
  );
end;
$$ language plpgsql security definer
set search_path = public;

create or replace function public.register_public_campaign_signup(
  slug_input text,
  campaign_id_input text,
  customer_name_input text,
  customer_email_input text default null,
  customer_mobile_input text default null
)
returns jsonb as $$
declare
  owner_row record;
  campaign_row public.campaigns%rowtype;
  customer_row public.customers%rowtype;
  existing_card_row record;
  normalized_name text;
  normalized_email text;
  normalized_mobile text;
  now_ts timestamptz := now();
  new_card_id text;
  new_unique_id uuid;
begin
  normalized_name := trim(coalesce(customer_name_input, ''));
  normalized_email := nullif(lower(trim(coalesce(customer_email_input, ''))), '');
  normalized_mobile := nullif(regexp_replace(coalesce(customer_mobile_input, ''), '[^0-9]+', '', 'g'), '');

  if normalized_name = '' then
    return jsonb_build_object('outcome', 'error', 'error', 'Name is required.');
  end if;

  select id, slug, business_name
  into owner_row
  from public.profiles
  where slug = slug_input and role = 'owner';
  if not found then
    return jsonb_build_object('outcome', 'error', 'error', 'Business not found.');
  end if;

  select *
  into campaign_row
  from public.campaigns
  where id = campaign_id_input
    and owner_id = owner_row.id;
  if not found then
    return jsonb_build_object('outcome', 'error', 'error', 'Campaign not found.');
  end if;

  if normalized_email is not null or normalized_mobile is not null then
    select *
    into customer_row
    from public.customers c
    where c.owner_id = owner_row.id
      and (
        (normalized_email is not null and nullif(lower(trim(c.email)), '') = normalized_email)
        or
        (normalized_mobile is not null and nullif(regexp_replace(coalesce(c.mobile, ''), '[^0-9]+', '', 'g'), '') = normalized_mobile)
      )
    order by c.created_at asc
    limit 1;
  end if;

  if customer_row.id is not null then
    select ic.unique_id
    into existing_card_row
    from public.issued_cards ic
    where ic.owner_id = owner_row.id
      and ic.campaign_id = campaign_row.id
      and ic.customer_id = customer_row.id
      and ic.status = 'Active'
    order by ic.created_at asc
    limit 1;

    if found then
      return jsonb_build_object('outcome', 'redirect_existing', 'uniqueId', existing_card_row.unique_id);
    end if;
  end if;

  if campaign_row.is_enabled = false then
    return jsonb_build_object('outcome', 'campaign_disabled_no_existing');
  end if;

  if customer_row.id is null then
    insert into public.customers (id, owner_id, name, email, mobile, status)
    values (
      gen_random_uuid()::text,
      owner_row.id,
      normalized_name,
      coalesce(normalized_email, ''),
      normalized_mobile,
      'Active'
    )
    returning * into customer_row;
  end if;

  new_card_id := gen_random_uuid()::text;
  new_unique_id := gen_random_uuid();

  insert into public.issued_cards (
    id,
    unique_id,
    customer_id,
    campaign_id,
    owner_id,
    campaign_name,
    stamps,
    last_visit,
    status,
    template_snapshot
  )
  values (
    new_card_id,
    new_unique_id,
    customer_row.id,
    campaign_row.id,
    owner_row.id,
    campaign_row.name,
    0,
    current_date,
    'Active',
    jsonb_build_object(
      'id', campaign_row.id,
      'name', campaign_row.name,
      'description', campaign_row.description,
      'rewardName', campaign_row.reward_name,
      'tagline', campaign_row.tagline,
      'backgroundImage', campaign_row.background_image,
      'backgroundOpacity', campaign_row.background_opacity,
      'logoImage', campaign_row.logo_image,
      'showLogo', campaign_row.show_logo,
      'titleSize', campaign_row.title_size,
      'iconKey', campaign_row.icon_key,
      'colors', campaign_row.colors,
      'totalStamps', campaign_row.total_stamps,
      'social', campaign_row.social
    )
  );

  insert into public.transactions (
    id,
    card_id,
    type,
    amount,
    date,
    "timestamp",
    title
  )
  values (
    gen_random_uuid()::text,
    new_card_id,
    'issued',
    0,
    to_char(now_ts, 'Mon FMDD, YYYY FMHH12:MI AM'),
    floor(extract(epoch from now_ts) * 1000)::bigint,
    'Card Issued'
  );

  return jsonb_build_object('outcome', 'issued', 'uniqueId', new_unique_id);
end;
$$ language plpgsql security definer
set search_path = public;

create or replace function public.delete_campaign_preserve_cards(campaign_id_input text)
returns jsonb as $$
declare
  campaign_row public.campaigns%rowtype;
  campaign_snapshot jsonb;
begin
  select *
  into campaign_row
  from public.campaigns
  where id = campaign_id_input
    and owner_id = auth.uid();

  if not found then
    raise exception 'Campaign not found or not owned by current user';
  end if;

  campaign_snapshot := jsonb_build_object(
    'id', campaign_row.id,
    'name', campaign_row.name,
    'description', campaign_row.description,
    'rewardName', campaign_row.reward_name,
    'tagline', campaign_row.tagline,
    'backgroundImage', campaign_row.background_image,
    'backgroundOpacity', campaign_row.background_opacity,
    'logoImage', campaign_row.logo_image,
    'showLogo', campaign_row.show_logo,
    'titleSize', campaign_row.title_size,
    'iconKey', campaign_row.icon_key,
    'colors', campaign_row.colors,
    'totalStamps', campaign_row.total_stamps,
    'social', campaign_row.social
  );

  update public.issued_cards
  set template_snapshot = coalesce(template_snapshot, campaign_snapshot),
      campaign_name = coalesce(nullif(campaign_name, ''), campaign_row.name)
  where campaign_id = campaign_row.id;

  delete from public.campaigns
  where id = campaign_row.id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer
set search_path = public;


-- 14. GET PUBLIC CARD DATA (RPC)
create or replace function public.get_public_card(slug_input text, card_unique_id uuid)
returns jsonb as $$
declare
  owner_row record;
  card_row record;
  customer_row record;
  campaign_payload jsonb;
  history_data jsonb;
begin
  select id, slug, business_name into owner_row
  from public.profiles where slug = slug_input and role = 'owner';
  if not found then return null; end if;

  select * into card_row
  from public.issued_cards where unique_id = card_unique_id and owner_id = owner_row.id;
  if not found then return null; end if;

  select * into customer_row
  from public.customers where id = card_row.customer_id;
  if not found then return null; end if;

  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'description', c.description,
    'reward_name', c.reward_name,
    'tagline', c.tagline,
    'background_image', c.background_image,
    'background_opacity', c.background_opacity,
    'logo_image', c.logo_image,
    'show_logo', c.show_logo,
    'title_size', c.title_size,
    'icon_key', c.icon_key,
    'colors', c.colors,
    'total_stamps', c.total_stamps,
    'social', c.social
  )
  into campaign_payload
  from public.campaigns c
  where c.id = card_row.campaign_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', t.id, 'type', t.type, 'amount', t.amount,
      'date', t.date, 'timestamp', t."timestamp", 'title', t.title
    ) order by t."timestamp"
  ), '[]'::jsonb)
  into history_data
  from public.transactions t where t.card_id = card_row.id;

  return jsonb_build_object(
    'card', jsonb_build_object(
      'id', card_row.id, 'uniqueId', card_row.unique_id,
      'campaignId', card_row.campaign_id, 'campaignName', card_row.campaign_name,
      'stamps', card_row.stamps, 'lastVisit', card_row.last_visit,
      'status', card_row.status, 'completedDate', card_row.completed_date,
      'templateSnapshot', card_row.template_snapshot,
      'history', history_data
    ),
    'customer', jsonb_build_object(
      'id', customer_row.id, 'name', customer_row.name
    ),
    'campaign', campaign_payload
  );
end;
$$ language plpgsql security definer
set search_path = public;

-- 15. PENDING DISCOUNT CLAIMS (RPC)
-- Staff/owner cashier queue for the reverse-scan discount flow. Resolves the
-- caller's effective owner (themselves for owners, their employer for staff)
-- so transactions stay isolated between venues without needing a broad
-- profiles read policy to expose customer names.
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

-- 16. DISCOUNT CLAIM HISTORY (RPCs)
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

-- 17. POINTS LEDGER (TABLE + RPC)
-- Manual end-of-month points awarded by a Stampee-operator admin, based on
-- CSV reports the venues send in (there's no POS integration to read stamps
-- from directly). An immutable append-only log rather than a mutable
-- balance column, so every award/redemption stays auditable.
create table if not exists public.points_ledger (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  points integer not null check (points <> 0),
  description text not null,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists points_ledger_customer_id_idx on public.points_ledger(customer_id);

alter table public.points_ledger enable row level security;

drop policy if exists "Customers can read own points ledger" on public.points_ledger;
create policy "Customers can read own points ledger"
  on public.points_ledger for select
  using (customer_id = (select auth.uid()));

drop policy if exists "Admins can read points ledger" on public.points_ledger;
create policy "Admins can read points ledger"
  on public.points_ledger for select
  using ((select public.current_user_role()) = 'admin');

drop policy if exists "Admins can insert points ledger" on public.points_ledger;
create policy "Admins can insert points ledger"
  on public.points_ledger for insert
  with check ((select public.current_user_role()) = 'admin');

create or replace function public.get_customer_points_balance(customer_id_input uuid)
returns integer as $$
declare
  caller_role text;
begin
  select role into caller_role from public.profiles where id = (select auth.uid());

  if (select auth.uid()) <> customer_id_input and (caller_role is null or caller_role <> 'admin') then
    return null;
  end if;

  return coalesce(
    (select sum(points) from public.points_ledger where customer_id = customer_id_input),
    0
  );
end;
$$ language plpgsql security definer
set search_path = public;

grant execute on function public.get_customer_points_balance(uuid) to authenticated;
