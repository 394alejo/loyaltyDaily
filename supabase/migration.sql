-- ============================================================
-- Stampee: Full Database Schema
-- Fresh install script for new Supabase projects.
-- Drops and recreates all app tables cleanly.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ============================================================
-- DROP EXISTING OBJECTS (in dependency order)
-- ============================================================
drop trigger if exists on_auth_user_created on auth.users;

do $$ begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'issued_cards'
  ) then
    drop trigger if exists issued_cards_block_disabled_campaign on public.issued_cards;
  end if;
end $$;

drop function if exists public.handle_new_user() cascade;
drop function if exists public.current_staff_owner_id() cascade;
drop function if exists public.prevent_issuing_disabled_campaign_card() cascade;
drop function if exists public.activate_license_key(text) cascade;
drop function if exists public.get_scan_entry_context(text, uuid) cascade;
drop function if exists public.inspect_scanned_card(uuid) cascade;
drop function if exists public.create_staff_account(text, text, text) cascade;
drop function if exists public.update_staff_pin(uuid, text) cascade;
drop function if exists public.delete_staff_account(uuid) cascade;
drop function if exists public.delete_own_account() cascade;
drop function if exists public.is_slug_available(text) cascade;
drop function if exists public.get_public_campaign_signup_context(text, text) cascade;
drop function if exists public.register_public_campaign_signup(text, text, text, text, text) cascade;
drop function if exists public.delete_campaign_preserve_cards(text) cascade;
drop function if exists public.get_public_card(text, uuid) cascade;

drop table if exists public.transactions cascade;
drop table if exists public.issued_cards cascade;
drop table if exists public.license_keys cascade;
drop table if exists public.customers cascade;
drop table if exists public.campaigns cascade;
drop table if exists public.profiles cascade;

-- ============================================================
-- 1. PROFILES TABLE
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  business_name text not null,
  email text not null,
  slug text unique,
  role text not null default 'owner' check (role in ('owner', 'staff')),
  owner_id uuid references public.profiles(id) on delete cascade,
  status text not null default 'unverified' check (status in ('unverified', 'verified')),
  access text not null default 'active' check (access in ('active', 'disabled')),
  tier text not null default 'free' check (tier in ('free', 'pro')),
  tier_expires_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create function public.current_staff_owner_id()
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

create policy "Users can read own profile"
  on public.profiles for select
  using ((select auth.uid()) = id);

create policy "Owners can read own staff profiles"
  on public.profiles for select
  using (role = 'staff' and owner_id = (select auth.uid()));

create policy "Staff can read owner profile"
  on public.profiles for select
  using (id = (select public.current_staff_owner_id()));

create policy "Users can update own profile"
  on public.profiles for update
  using ((select auth.uid()) = id);

create policy "Owners can update own staff profiles"
  on public.profiles for update
  using (role = 'staff' and owner_id = (select auth.uid()));

create policy "Owners can insert staff profiles"
  on public.profiles for insert
  with check (role = 'staff' and owner_id = (select auth.uid()));

create policy "Allow trigger insert for new signups"
  on public.profiles for insert
  with check (auth.uid() = id);

create function public.handle_new_user()
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

  insert into public.profiles (id, business_name, email, slug, role, owner_id, status, access, tier)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'business_name', ''),
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
$$ language plpgsql security definer set search_path = public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- 2. CAMPAIGNS TABLE
-- ============================================================
create table public.campaigns (
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
  created_at timestamptz not null default now()
);

alter table public.campaigns enable row level security;

create policy "Owners can manage own campaigns"
  on public.campaigns for all
  using ((select auth.uid()) = owner_id);

create policy "Staff can read owner campaigns"
  on public.campaigns for select
  using (owner_id = (select owner_id from public.profiles where id = auth.uid()));

-- ============================================================
-- 3. CUSTOMERS TABLE
-- ============================================================
create table public.customers (
  id text primary key default gen_random_uuid()::text,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  email text not null,
  mobile text,
  status text not null default 'Active' check (status in ('Active', 'Inactive')),
  created_at timestamptz not null default now()
);

alter table public.customers enable row level security;

create policy "Owners can manage own customers"
  on public.customers for all
  using (auth.uid() = owner_id);

create policy "Staff can read owner customers"
  on public.customers for select
  using (owner_id = (select owner_id from public.profiles where id = auth.uid()));

create policy "Staff can update owner customers"
  on public.customers for update
  using (owner_id = (select owner_id from public.profiles where id = auth.uid()));

-- ============================================================
-- 4. ISSUED CARDS TABLE
-- ============================================================
create table public.issued_cards (
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

alter table public.issued_cards enable row level security;

create function public.prevent_issuing_disabled_campaign_card()
returns trigger as $$
declare
  campaign_enabled boolean;
begin
  if new.campaign_id is null then
    return new;
  end if;
  select c.is_enabled into campaign_enabled
  from public.campaigns c where c.id = new.campaign_id;
  if found and campaign_enabled = false then
    raise exception 'CAMPAIGN_DISABLED: This campaign is disabled and cannot issue new cards.';
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

create trigger issued_cards_block_disabled_campaign
  before insert on public.issued_cards
  for each row execute function public.prevent_issuing_disabled_campaign_card();

create policy "Owners can manage own issued cards"
  on public.issued_cards for all
  using (auth.uid() = owner_id);

create policy "Staff can read owner issued cards"
  on public.issued_cards for select
  using (owner_id = (select owner_id from public.profiles where id = auth.uid()));

create policy "Staff can update owner issued cards"
  on public.issued_cards for update
  using (owner_id = (select owner_id from public.profiles where id = auth.uid()));

-- ============================================================
-- 5. TRANSACTIONS TABLE
-- ============================================================
create table public.transactions (
  id text primary key default gen_random_uuid()::text,
  card_id text not null references public.issued_cards(id) on delete cascade,
  type text not null check (type in ('stamp_add', 'stamp_remove', 'redeem', 'issued')),
  amount int not null default 0,
  date text not null,
  "timestamp" bigint not null,
  title text not null,
  remarks text,
  actor_id uuid,
  actor_name text,
  actor_role text
);

alter table public.transactions enable row level security;

create policy "Owners can manage transactions for own cards"
  on public.transactions for all
  using (
    card_id in (select id from public.issued_cards where owner_id = (select auth.uid()))
  );

create policy "Staff can read owner transactions"
  on public.transactions for select
  using (
    card_id in (
      select ic.id from public.issued_cards ic
      where ic.owner_id = (select owner_id from public.profiles where id = (select auth.uid()))
    )
  );

create policy "Staff can insert transactions for owner cards"
  on public.transactions for insert
  with check (
    card_id in (
      select ic.id from public.issued_cards ic
      where ic.owner_id = (select owner_id from public.profiles where id = (select auth.uid()))
    )
  );

-- ============================================================
-- 6. LICENSE KEYS TABLE
-- ============================================================
create table public.license_keys (
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

create policy "Users can read own license keys"
  on public.license_keys for select
  using (profile_id = (select auth.uid()));

create policy "Users can claim a license key"
  on public.license_keys for update
  using (profile_id is null or profile_id = auth.uid());

-- ============================================================
-- 7. STORAGE BUCKET
-- ============================================================
insert into storage.buckets (id, name, public)
values ('campaign-assets', 'campaign-assets', true)
on conflict (id) do update set public = excluded.public;

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

-- ============================================================
-- 8. RPC FUNCTIONS
-- ============================================================
create function public.activate_license_key(key_input text)
returns jsonb as $$
declare
  key_row public.license_keys%rowtype;
  one_year_later timestamptz;
begin
  select * into key_row
  from public.license_keys
  where license_key = key_input and status = 'active' and profile_id is null
  for update;

  if not found then
    return jsonb_build_object('success', false, 'error', 'Invalid or already used license key');
  end if;

  one_year_later := now() + interval '1 year';

  update public.license_keys
  set profile_id = auth.uid(), activated_at = now(), expires_at = one_year_later
  where id = key_row.id;

  update public.profiles
  set tier = 'pro', tier_expires_at = one_year_later
  where id = auth.uid();

  return jsonb_build_object('success', true, 'expires_at', one_year_later);
end;
$$ language plpgsql security definer set search_path = public;

create function public.get_scan_entry_context(slug_input text, card_unique_id uuid)
returns jsonb as $$
declare
  owner_row record;
  card_row record;
begin
  select id, slug, business_name into owner_row
  from public.profiles where slug = slug_input and role = 'owner';
  if not found then return null; end if;

  select unique_id into card_row
  from public.issued_cards where unique_id = card_unique_id and owner_id = owner_row.id;
  if not found then return null; end if;

  return jsonb_build_object(
    'owner', jsonb_build_object('id', owner_row.id, 'slug', owner_row.slug, 'businessName', owner_row.business_name),
    'card', jsonb_build_object('uniqueId', card_row.unique_id)
  );
end;
$$ language plpgsql security definer set search_path = public;

create function public.inspect_scanned_card(card_unique_id uuid)
returns jsonb as $$
declare
  actor_row record;
  card_row record;
  actor_owner_id uuid;
begin
  select id, role, owner_id into actor_row
  from public.profiles where id = auth.uid();
  if not found then return jsonb_build_object('status', 'missing'); end if;

  actor_owner_id := case when actor_row.role = 'owner' then actor_row.id else actor_row.owner_id end;
  if actor_owner_id is null then return jsonb_build_object('status', 'missing'); end if;

  select owner_id into card_row from public.issued_cards where unique_id = card_unique_id;
  if not found then return jsonb_build_object('status', 'missing'); end if;
  if card_row.owner_id <> actor_owner_id then return jsonb_build_object('status', 'foreign'); end if;

  return jsonb_build_object('status', 'owned');
end;
$$ language plpgsql security definer set search_path = public;

create function public.create_staff_account(staff_email text, staff_pin text, staff_name text)
returns uuid as $$
declare
  new_uid uuid := gen_random_uuid();
  owner_uid uuid := auth.uid();
begin
  if not exists (select 1 from public.profiles where id = owner_uid and role = 'owner') then
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
    new_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    lower(trim(staff_email)), crypt(staff_pin, gen_salt('bf')), now(),
    jsonb_build_object('role', 'staff', 'owner_id', owner_uid::text, 'business_name', staff_name),
    jsonb_build_object('provider', 'email', 'providers', array_to_json(array['email'])),
    now(), now(), false
  );

  insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  values (
    new_uid, new_uid,
    jsonb_build_object('sub', new_uid::text, 'email', lower(trim(staff_email))),
    'email', new_uid::text, now(), now(), now()
  );

  return new_uid;
end;
$$ language plpgsql security definer set search_path = public;

create function public.update_staff_pin(staff_id uuid, new_pin text)
returns void as $$
begin
  if not exists (
    select 1 from public.profiles where id = staff_id and role = 'staff' and owner_id = auth.uid()
  ) then
    raise exception 'Not your staff member';
  end if;
  update auth.users set encrypted_password = crypt(new_pin, gen_salt('bf')), updated_at = now()
  where id = staff_id;
end;
$$ language plpgsql security definer set search_path = public;

create function public.delete_staff_account(staff_id uuid)
returns void as $$
begin
  if not exists (
    select 1 from public.profiles where id = staff_id and role = 'staff' and owner_id = auth.uid()
  ) then
    raise exception 'Not your staff member';
  end if;
  delete from auth.users where id = staff_id;
end;
$$ language plpgsql security definer set search_path = public;

create function public.delete_own_account()
returns void as $$
declare
  uid uuid := auth.uid();
begin
  delete from auth.users where id in (
    select id from public.profiles where owner_id = uid and role = 'staff'
  );
  delete from auth.users where id = uid;
end;
$$ language plpgsql security definer set search_path = public;

create function public.is_slug_available(slug_input text)
returns boolean as $$
begin
  return not exists (
    select 1 from public.profiles
    where slug = lower(trim(slug_input)) and role = 'owner'
  );
end;
$$ language plpgsql security definer set search_path = public;

create function public.get_public_campaign_signup_context(slug_input text, campaign_id_input text)
returns jsonb as $$
declare
  owner_row record;
  campaign_row record;
begin
  select id, slug, business_name into owner_row
  from public.profiles where slug = slug_input and role = 'owner';
  if not found then return null; end if;

  select id, name, is_enabled into campaign_row
  from public.campaigns where id = campaign_id_input and owner_id = owner_row.id;
  if not found then return null; end if;

  return jsonb_build_object(
    'owner', jsonb_build_object('id', owner_row.id, 'slug', owner_row.slug, 'businessName', owner_row.business_name),
    'campaign', jsonb_build_object('id', campaign_row.id, 'name', campaign_row.name, 'isEnabled', campaign_row.is_enabled)
  );
end;
$$ language plpgsql security definer set search_path = public;

create function public.register_public_campaign_signup(
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

  select id, slug, business_name into owner_row
  from public.profiles where slug = slug_input and role = 'owner';
  if not found then return jsonb_build_object('outcome', 'error', 'error', 'Business not found.'); end if;

  select * into campaign_row
  from public.campaigns where id = campaign_id_input and owner_id = owner_row.id;
  if not found then return jsonb_build_object('outcome', 'error', 'error', 'Campaign not found.'); end if;

  if normalized_email is not null or normalized_mobile is not null then
    select * into customer_row
    from public.customers c
    where c.owner_id = owner_row.id
      and (
        (normalized_email is not null and nullif(lower(trim(c.email)), '') = normalized_email)
        or
        (normalized_mobile is not null and nullif(regexp_replace(coalesce(c.mobile, ''), '[^0-9]+', '', 'g'), '') = normalized_mobile)
      )
    order by c.created_at asc limit 1;
  end if;

  if customer_row.id is not null then
    select ic.unique_id into existing_card_row
    from public.issued_cards ic
    where ic.owner_id = owner_row.id
      and ic.campaign_id = campaign_row.id
      and ic.customer_id = customer_row.id
      and ic.status = 'Active'
    order by ic.created_at asc limit 1;

    if found then
      return jsonb_build_object('outcome', 'redirect_existing', 'uniqueId', existing_card_row.unique_id);
    end if;
  end if;

  if campaign_row.is_enabled = false then
    return jsonb_build_object('outcome', 'campaign_disabled_no_existing');
  end if;

  if customer_row.id is null then
    insert into public.customers (id, owner_id, name, email, mobile, status)
    values (gen_random_uuid()::text, owner_row.id, normalized_name, coalesce(normalized_email, ''), normalized_mobile, 'Active')
    returning * into customer_row;
  end if;

  new_card_id := gen_random_uuid()::text;
  new_unique_id := gen_random_uuid();

  insert into public.issued_cards (id, unique_id, customer_id, campaign_id, owner_id, campaign_name, stamps, last_visit, status, template_snapshot)
  values (
    new_card_id, new_unique_id, customer_row.id, campaign_row.id, owner_row.id, campaign_row.name,
    0, current_date, 'Active',
    jsonb_build_object(
      'id', campaign_row.id, 'name', campaign_row.name, 'description', campaign_row.description,
      'rewardName', campaign_row.reward_name, 'tagline', campaign_row.tagline,
      'backgroundImage', campaign_row.background_image, 'backgroundOpacity', campaign_row.background_opacity,
      'logoImage', campaign_row.logo_image, 'showLogo', campaign_row.show_logo,
      'titleSize', campaign_row.title_size, 'iconKey', campaign_row.icon_key,
      'colors', campaign_row.colors, 'totalStamps', campaign_row.total_stamps, 'social', campaign_row.social
    )
  );

  insert into public.transactions (id, card_id, type, amount, date, "timestamp", title)
  values (
    gen_random_uuid()::text, new_card_id, 'issued', 0,
    to_char(now_ts, 'Mon FMDD, YYYY FMHH12:MI AM'),
    floor(extract(epoch from now_ts) * 1000)::bigint,
    'Card Issued'
  );

  return jsonb_build_object('outcome', 'issued', 'uniqueId', new_unique_id);
end;
$$ language plpgsql security definer set search_path = public;

create function public.delete_campaign_preserve_cards(campaign_id_input text)
returns jsonb as $$
declare
  campaign_row public.campaigns%rowtype;
  campaign_snapshot jsonb;
begin
  select * into campaign_row
  from public.campaigns where id = campaign_id_input and owner_id = auth.uid();
  if not found then raise exception 'Campaign not found or not owned by current user'; end if;

  campaign_snapshot := jsonb_build_object(
    'id', campaign_row.id, 'name', campaign_row.name, 'description', campaign_row.description,
    'rewardName', campaign_row.reward_name, 'tagline', campaign_row.tagline,
    'backgroundImage', campaign_row.background_image, 'backgroundOpacity', campaign_row.background_opacity,
    'logoImage', campaign_row.logo_image, 'showLogo', campaign_row.show_logo,
    'titleSize', campaign_row.title_size, 'iconKey', campaign_row.icon_key,
    'colors', campaign_row.colors, 'totalStamps', campaign_row.total_stamps, 'social', campaign_row.social
  );

  update public.issued_cards
  set template_snapshot = coalesce(template_snapshot, campaign_snapshot),
      campaign_name = coalesce(nullif(campaign_name, ''), campaign_row.name)
  where campaign_id = campaign_row.id;

  delete from public.campaigns where id = campaign_row.id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

create function public.get_public_card(slug_input text, card_unique_id uuid)
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

  select * into customer_row from public.customers where id = card_row.customer_id;
  if not found then return null; end if;

  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'description', c.description,
    'reward_name', c.reward_name, 'tagline', c.tagline,
    'background_image', c.background_image, 'background_opacity', c.background_opacity,
    'logo_image', c.logo_image, 'show_logo', c.show_logo,
    'title_size', c.title_size, 'icon_key', c.icon_key,
    'colors', c.colors, 'total_stamps', c.total_stamps, 'social', c.social
  ) into campaign_payload
  from public.campaigns c where c.id = card_row.campaign_id;

  select coalesce(jsonb_agg(
    jsonb_build_object('id', t.id, 'type', t.type, 'amount', t.amount, 'date', t.date, 'timestamp', t."timestamp", 'title', t.title)
    order by t."timestamp"
  ), '[]'::jsonb) into history_data
  from public.transactions t where t.card_id = card_row.id;

  return jsonb_build_object(
    'card', jsonb_build_object(
      'id', card_row.id, 'uniqueId', card_row.unique_id,
      'campaignId', card_row.campaign_id, 'campaignName', card_row.campaign_name,
      'stamps', card_row.stamps, 'lastVisit', card_row.last_visit,
      'status', card_row.status, 'completedDate', card_row.completed_date,
      'templateSnapshot', card_row.template_snapshot, 'history', history_data
    ),
    'customer', jsonb_build_object('id', customer_row.id, 'name', customer_row.name),
    'campaign', campaign_payload
  );
end;
$$ language plpgsql security definer set search_path = public;
