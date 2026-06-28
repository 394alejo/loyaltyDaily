-- ============================================================
-- Stampee: Demo Admin Seed Script
-- Local/development use only.
-- ============================================================
-- Run this in the Supabase SQL Editor AFTER running migration.sql.
-- This creates a single demo admin (owner) account with known
-- credentials for local or development environments only.
--
-- Demo credentials:
--   Email   : admin@stampee.local
--   Password: Admin1234
--   Slug    : demo
-- ============================================================

do $$
declare
  v_uid uuid := gen_random_uuid();
  v_email text := 'admin2@daily.com';
  v_password text := 'daily1234';
  v_business_name text := 'Demo Business';
  v_slug text := 'demo3';
begin
  -- Clean up any previous demo attempts (old emails or slug conflicts)
  delete from auth.users where email in ('admin@daily', 'admin@daily.com', v_email);
  delete from public.profiles where slug = v_slug;

  -- Create the Supabase auth user
  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_user_meta_data,
    raw_app_meta_data,
    created_at,
    updated_at,
    is_sso_user
  ) values (
    v_uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    crypt(v_password, gen_salt('bf')),
    now(),
    jsonb_build_object(
      'role', 'owner',
      'business_name', v_business_name,
      'slug', v_slug
    ),
    jsonb_build_object('provider', 'email', 'providers', array_to_json(array['email'])),
    now(),
    now(),
    false
  );

  -- Create the identity record (required for email/password sign-in)
  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    v_uid,
    v_uid,
    jsonb_build_object('sub', v_uid::text, 'email', v_email),
    'email',
    v_email,
    now(),
    now(),
    now()
  );

  -- The handle_new_user trigger auto-creates the profile row.
  -- Update it to set verified status and the correct slug.
  update public.profiles
  set
    status = 'verified',
    slug   = v_slug,
    tier   = 'free'
  where id = v_uid;

  raise notice 'Demo admin created successfully.';
  raise notice '  Email   : %', v_email;
  raise notice '  Password: %', v_password;
  raise notice '  Slug    : %', v_slug;
end;
$$;
