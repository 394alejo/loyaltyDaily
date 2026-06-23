-- Stampee upgrade script: add the admin role and the points_ledger table
-- for the end-of-month manual points award tool.
-- New projects should use migration.sql instead.

-- 1. Admin role (Stampee-operator account, manually provisioned via SQL —
-- there is no self-serve signup for it).
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('owner', 'staff', 'customer', 'admin'));

create or replace function public.current_user_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from public.profiles where id = (select auth.uid())
$$;

drop policy if exists "Admins can read customer profiles" on public.profiles;
create policy "Admins can read customer profiles"
  on public.profiles for select
  using (
    role = 'customer' and (select public.current_user_role()) = 'admin'
  );

-- 2. Points ledger: immutable append-only log of manually awarded/redeemed
-- points, since there's no POS integration to read stamps from directly.
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
