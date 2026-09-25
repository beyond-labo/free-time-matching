create extension if not exists btree_gist;

create table public.availability_slots (
  id uuid primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  category text,
  visibility text not null default 'privateUntilAccepted',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint availability_slots_interval_check check (end_at > start_at),
  constraint availability_slots_quarter_hour_check check (
    mod(extract(epoch from start_at)::bigint, 900) = 0
    and mod(extract(epoch from end_at)::bigint, 900) = 0
  ),
  constraint availability_slots_category_check check (category is null or category in ('game', 'meal', 'call', 'work')),
  constraint availability_slots_visibility_check check (visibility in ('privateUntilAccepted', 'shareOnHosting'))
);

alter table public.availability_slots
  add constraint availability_slots_no_overlap
  exclude using gist (
    owner_user_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  );

create index availability_slots_owner_start on public.availability_slots (owner_user_id, start_at);

create trigger availability_slots_set_updated_at
before update on public.availability_slots
for each row execute function private.set_updated_at();

create or replace function private.validate_availability_window()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.start_at < now() or new.end_at > now() + interval '14 days' then
    raise exception using errcode = '23514', message = 'availability_invalid';
  end if;
  return new;
end;
$$;

revoke all on function private.validate_availability_window() from public;

create trigger availability_slots_validate_window
before insert or update of start_at, end_at on public.availability_slots
for each row execute function private.validate_availability_window();

alter table public.availability_slots enable row level security;
revoke all on table public.availability_slots from anon;
grant select, insert, update, delete on table public.availability_slots to authenticated;

create policy availability_slots_select_own on public.availability_slots
for select to authenticated using (
  owner_user_id = (select auth.uid()) and (select public.is_account_active())
);
create policy availability_slots_insert_own on public.availability_slots
for insert to authenticated with check (
  owner_user_id = (select auth.uid()) and (select public.is_account_active())
);
create policy availability_slots_update_own on public.availability_slots
for update to authenticated
using (owner_user_id = (select auth.uid()) and (select public.is_account_active()))
with check (owner_user_id = (select auth.uid()) and (select public.is_account_active()));
create policy availability_slots_delete_own on public.availability_slots
for delete to authenticated using (
  owner_user_id = (select auth.uid()) and (select public.is_account_active())
);
