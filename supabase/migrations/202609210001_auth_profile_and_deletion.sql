create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  preset_icon_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_profiles_nickname_check check (
    nickname = btrim(nickname)
    -- PostgreSQL char_length counts code points, not user-perceived graphemes.
    -- The API Domain enforces the public 1..20 grapheme contract; this wider
    -- bound accepts twenty joined emoji while still bounding stored input.
    and char_length(nickname) between 1 and 160
  ),
  constraint user_profiles_preset_icon_key_check check (
    preset_icon_key in (
      'sun.max.fill',
      'leaf.fill',
      'gamecontroller.fill',
      'figure.run'
    )
  )
);

create table public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  idempotency_key text not null,
  reference text not null unique,
  status_token_hash text not null,
  status text not null default 'accepted',
  message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint account_deletion_idempotency_key_check check (
    char_length(idempotency_key) between 8 and 200
  ),
  constraint account_deletion_status_token_hash_check check (
    status_token_hash ~ '^[0-9a-f]{64}$'
  ),
  constraint account_deletion_status_check check (
    status in ('accepted', 'processing', 'completed', 'action_required')
  ),
  constraint account_deletion_user_operation_unique unique (user_id, idempotency_key)
);

create index account_deletion_requests_user_id_idx
  on public.account_deletion_requests (user_id);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger user_profiles_set_updated_at
before update on public.user_profiles
for each row execute function private.set_updated_at();

create trigger account_deletion_requests_set_updated_at
before update on public.account_deletion_requests
for each row execute function private.set_updated_at();

create or replace function private.account_is_active(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1
    from public.account_deletion_requests
    where user_id = target_user_id
  );
$$;

revoke all on function private.account_is_active(uuid) from public;

create or replace function public.is_account_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.account_is_active(auth.uid());
$$;

revoke all on function public.is_account_active() from public;
grant execute on function public.is_account_active() to authenticated;

alter table public.user_profiles enable row level security;
alter table public.account_deletion_requests enable row level security;

revoke all on table public.user_profiles from anon, authenticated;
grant select, insert, update on table public.user_profiles to authenticated;
grant select, insert, update, delete on table public.user_profiles to service_role;

create policy user_profiles_select_own_active
on public.user_profiles
for select
to authenticated
using (
  (select auth.uid()) = user_id
  and (select public.is_account_active())
);

create policy user_profiles_insert_own_active
on public.user_profiles
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and (select public.is_account_active())
);

create policy user_profiles_update_own_active
on public.user_profiles
for update
to authenticated
using (
  (select auth.uid()) = user_id
  and (select public.is_account_active())
)
with check (
  (select auth.uid()) = user_id
  and (select public.is_account_active())
);

revoke all on table public.account_deletion_requests from anon, authenticated;
grant select, insert, update, delete on table public.account_deletion_requests to service_role;

create or replace function public.get_account_deletion_status(
  p_reference text,
  p_status_token text
)
returns table(reference text, status text, message text)
language sql
stable
security definer
set search_path = ''
as $$
  select request.reference, request.status, request.message
  from public.account_deletion_requests as request
  where request.reference = p_reference
    and request.status_token_hash = encode(
      extensions.digest(convert_to(p_status_token, 'UTF8'), 'sha256'),
      'hex'
    );
$$;

revoke all on function public.get_account_deletion_status(text, text) from public;
grant execute on function public.get_account_deletion_status(text, text) to anon, authenticated;

comment on table public.user_profiles is
  'Minimal user profile. Authorization is enforced with auth.uid() and deletion-state RLS.';
comment on table public.account_deletion_requests is
  'Deletion receipt tombstone. It intentionally has no auth.users foreign key so status survives hard deletion.';
