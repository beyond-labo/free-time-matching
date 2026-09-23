create table public.friend_invite_codes (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  code text not null,
  code_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint friend_invite_codes_code_check check (
    code ~ '^HIMA(-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}){4}$'
  ),
  constraint friend_invite_codes_hash_check check (code_hash ~ '^[0-9a-f]{64}$'),
  constraint friend_invite_codes_expiry_check check (expires_at > created_at)
);

create unique index friend_invite_codes_one_active_per_owner
  on public.friend_invite_codes (owner_user_id)
  where revoked_at is null;

create index friend_invite_codes_owner_history
  on public.friend_invite_codes (owner_user_id, created_at desc);

create table public.friendship_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  pair_low uuid generated always as (least(requester_id, addressee_id)) stored,
  pair_high uuid generated always as (greatest(requester_id, addressee_id)) stored,
  status text not null default 'pending',
  version integer not null default 1,
  last_operation_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friendship_requests_distinct_users check (requester_id <> addressee_id),
  constraint friendship_requests_status_check check (
    status in ('pending', 'accepted', 'rejected', 'cancelled')
  ),
  constraint friendship_requests_version_check check (version >= 1)
);

create unique index friendship_requests_one_pending_pair
  on public.friendship_requests (pair_low, pair_high)
  where status = 'pending';

create index friendship_requests_requester_status
  on public.friendship_requests (requester_id, status, created_at desc);

create index friendship_requests_addressee_status
  on public.friendship_requests (addressee_id, status, created_at desc);

create table public.friendships (
  user_low_id uuid not null references auth.users(id) on delete cascade,
  user_high_id uuid not null references auth.users(id) on delete cascade,
  active boolean not null default true,
  version integer not null default 1,
  last_operation_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_low_id, user_high_id),
  constraint friendships_ordered_pair_check check (user_low_id < user_high_id),
  constraint friendships_version_check check (version >= 1)
);

create table public.friendship_operations (
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  operation_kind text not null,
  operation_target text not null,
  created_at timestamptz not null default now(),
  primary key (actor_user_id, operation_id),
  constraint friendship_operations_kind_check check (
    operation_kind in ('send', 'accept', 'reject', 'cancel', 'remove')
  )
);

create trigger friendship_requests_set_updated_at
before update on public.friendship_requests
for each row execute function private.set_updated_at();

create trigger friendships_set_updated_at
before update on public.friendships
for each row execute function private.set_updated_at();

alter table public.friend_invite_codes enable row level security;
alter table public.friendship_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.friendship_operations enable row level security;

revoke all on table public.friend_invite_codes from anon, authenticated;
revoke all on table public.friendship_requests from anon, authenticated;
revoke all on table public.friendships from anon, authenticated;
revoke all on table public.friendship_operations from anon, authenticated;

grant select, insert, update, delete on table public.friend_invite_codes to service_role;
grant select, insert, update, delete on table public.friendship_requests to service_role;
grant select, insert, update, delete on table public.friendships to service_role;
grant select, insert, update, delete on table public.friendship_operations to service_role;

create or replace function private.friendship_actor()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    raise exception 'friendship_unavailable';
  end if;
  if not private.account_is_active(actor_id) then
    raise exception 'account_deletion_in_progress';
  end if;
  if not exists (select 1 from public.user_profiles where user_id = actor_id) then
    raise exception 'friendship_unavailable';
  end if;
  return actor_id;
end;
$$;

revoke all on function private.friendship_actor() from public;

create or replace function private.friendship_snapshot_for(actor_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'invite_code', (
      select jsonb_build_object('value', code, 'expires_at', expires_at)
      from public.friend_invite_codes
      where owner_user_id = actor_id
        and revoked_at is null
        and expires_at > now()
      order by created_at desc
      limit 1
    ),
    'friends', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'profile', jsonb_build_object(
            'user_id', profile.user_id,
            'nickname', profile.nickname,
            'preset_icon_key', profile.preset_icon_key
          ),
          'version', relation.version,
          'created_at', relation.created_at
        ) order by profile.nickname, profile.user_id
      )
      from public.friendships relation
      join public.user_profiles profile
        on profile.user_id = case
          when relation.user_low_id = actor_id then relation.user_high_id
          else relation.user_low_id
        end
      where actor_id in (relation.user_low_id, relation.user_high_id)
        and relation.active
        and private.account_is_active(profile.user_id)
    ), '[]'::jsonb),
    'incoming_requests', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', request.id,
          'profile', jsonb_build_object(
            'user_id', profile.user_id,
            'nickname', profile.nickname,
            'preset_icon_key', profile.preset_icon_key
          ),
          'version', request.version,
          'created_at', request.created_at
        ) order by request.created_at desc
      )
      from public.friendship_requests request
      join public.user_profiles profile on profile.user_id = request.requester_id
      where request.addressee_id = actor_id
        and request.status = 'pending'
        and private.account_is_active(profile.user_id)
    ), '[]'::jsonb),
    'outgoing_requests', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', request.id,
          'profile', jsonb_build_object(
            'user_id', profile.user_id,
            'nickname', profile.nickname,
            'preset_icon_key', profile.preset_icon_key
          ),
          'version', request.version,
          'created_at', request.created_at
        ) order by request.created_at desc
      )
      from public.friendship_requests request
      join public.user_profiles profile on profile.user_id = request.addressee_id
      where request.requester_id = actor_id
        and request.status = 'pending'
        and private.account_is_active(profile.user_id)
    ), '[]'::jsonb)
  );
$$;

revoke all on function private.friendship_snapshot_for(uuid) from public;

create or replace function public.friendship_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.friendship_actor();
begin
  return private.friendship_snapshot_for(actor_id);
end;
$$;

create or replace function public.rotate_friend_invite_code(
  p_code text,
  p_code_hash text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.friendship_actor();
begin
  if p_code is null
    or p_code_hash is null
    or p_expires_at is null
    or p_code !~ '^HIMA(-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}){4}$'
    or p_code_hash !~ '^[0-9a-f]{64}$'
    or p_expires_at <= now()
    or p_expires_at > now() + interval '8 days'
  then
    raise exception 'friendship_unavailable';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor_id::text, 0));

  update public.friend_invite_codes
  set revoked_at = now()
  where owner_user_id = actor_id and revoked_at is null;

  insert into public.friend_invite_codes (owner_user_id, code, code_hash, expires_at)
  values (actor_id, p_code, p_code_hash, p_expires_at);

  return private.friendship_snapshot_for(actor_id);
end;
$$;

create or replace function public.ensure_friend_invite_code(
  p_code text,
  p_code_hash text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.friendship_actor();
begin
  if p_code is null
    or p_code_hash is null
    or p_expires_at is null
    or p_code !~ '^HIMA(-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}){4}$'
    or p_code_hash !~ '^[0-9a-f]{64}$'
    or p_expires_at <= now()
    or p_expires_at > now() + interval '8 days'
  then
    raise exception 'friendship_unavailable';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor_id::text, 0));
  if exists (
    select 1 from public.friend_invite_codes
    where owner_user_id = actor_id
      and revoked_at is null
      and expires_at > now()
  ) then
    return private.friendship_snapshot_for(actor_id);
  end if;

  update public.friend_invite_codes
  set revoked_at = now()
  where owner_user_id = actor_id and revoked_at is null;

  insert into public.friend_invite_codes (owner_user_id, code, code_hash, expires_at)
  values (actor_id, p_code, p_code_hash, p_expires_at);
  return private.friendship_snapshot_for(actor_id);
end;
$$;

create or replace function public.resolve_friend_invite_code(p_code_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.friendship_actor();
  target_profile public.user_profiles%rowtype;
begin
  select profile.* into target_profile
  from public.friend_invite_codes code
  join public.user_profiles profile on profile.user_id = code.owner_user_id
  where code.code_hash = p_code_hash
    and code.revoked_at is null
    and code.expires_at > now()
    and code.owner_user_id <> actor_id
    and private.account_is_active(code.owner_user_id)
  limit 1;

  if target_profile.user_id is null then
    raise exception 'invite_code_unavailable';
  end if;

  return jsonb_build_object(
    'user_id', target_profile.user_id,
    'nickname', target_profile.nickname,
    'preset_icon_key', target_profile.preset_icon_key
  );
end;
$$;

create or replace function public.send_friend_request(
  p_code_hash text,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.friendship_actor();
  target_id uuid;
  low_id uuid;
  high_id uuid;
  existing_kind text;
  existing_target text;
  operation_target text := 'code:' || p_code_hash;
begin
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invite_code_unavailable';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(actor_id::text || ':' || p_operation_id::text, 0)
  );
  select operation_kind, friendship_operations.operation_target
  into existing_kind, existing_target
  from public.friendship_operations
  where actor_user_id = actor_id and operation_id = p_operation_id;
  if existing_kind is not null then
    if existing_kind <> 'send' or existing_target <> operation_target then
      raise exception 'friendship_conflict';
    end if;
    return private.friendship_snapshot_for(actor_id);
  end if;

  select owner_user_id into target_id
  from public.friend_invite_codes
  where code_hash = p_code_hash
    and revoked_at is null
    and expires_at > now()
    and owner_user_id <> actor_id
    and private.account_is_active(owner_user_id)
  limit 1;
  if target_id is null then raise exception 'invite_code_unavailable'; end if;

  low_id := least(actor_id, target_id);
  high_id := greatest(actor_id, target_id);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(low_id::text || ':' || high_id::text, 1)
  );
  if exists (
    select 1 from public.friendships
    where user_low_id = low_id and user_high_id = high_id and active
  ) or exists (
    select 1 from public.friendship_requests
    where pair_low = low_id and pair_high = high_id and status = 'pending'
  ) then
    raise exception 'friendship_conflict';
  end if;

  insert into public.friendship_requests (
    requester_id, addressee_id, last_operation_id
  ) values (actor_id, target_id, p_operation_id);
  insert into public.friendship_operations (
    actor_user_id, operation_id, operation_kind, operation_target
  ) values (actor_id, p_operation_id, 'send', operation_target);

  return private.friendship_snapshot_for(actor_id);
end;
$$;

create or replace function public.transition_friend_request(
  p_request_id uuid,
  p_transition text,
  p_operation_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.friendship_actor();
  request_row public.friendship_requests%rowtype;
  existing_kind text;
  existing_target text;
  operation_target text := 'request:' || p_request_id::text
    || ':transition:' || p_transition || ':version:' || p_expected_version::text;
  low_id uuid;
  high_id uuid;
begin
  if p_request_id is null
    or p_operation_id is null
    or p_expected_version is null
    or p_expected_version < 1
    or p_transition is null
    or p_transition not in ('accept', 'reject', 'cancel')
  then
    raise exception 'friendship_unavailable';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(actor_id::text || ':' || p_operation_id::text, 0)
  );
  select operation_kind, friendship_operations.operation_target
  into existing_kind, existing_target
  from public.friendship_operations
  where actor_user_id = actor_id and operation_id = p_operation_id;
  if existing_kind is not null then
    if existing_kind <> p_transition or existing_target <> operation_target then
      raise exception 'friendship_conflict';
    end if;
    return private.friendship_snapshot_for(actor_id);
  end if;

  select * into request_row
  from public.friendship_requests
  where id = p_request_id
  for update;
  if request_row.id is null then raise exception 'friendship_unavailable'; end if;
  if p_transition = 'cancel' and request_row.requester_id <> actor_id then
    raise exception 'friendship_unavailable';
  end if;
  if p_transition in ('accept', 'reject') and request_row.addressee_id <> actor_id then
    raise exception 'friendship_unavailable';
  end if;
  if request_row.status <> 'pending' or request_row.version <> p_expected_version then
    raise exception 'friendship_conflict';
  end if;

  update public.friendship_requests
  set status = case p_transition
      when 'accept' then 'accepted'
      when 'reject' then 'rejected'
      else 'cancelled'
    end,
    version = version + 1,
    last_operation_id = p_operation_id
  where id = p_request_id;

  if p_transition = 'accept' then
    low_id := least(request_row.requester_id, request_row.addressee_id);
    high_id := greatest(request_row.requester_id, request_row.addressee_id);
    insert into public.friendships (user_low_id, user_high_id, last_operation_id)
    values (low_id, high_id, p_operation_id)
    on conflict (user_low_id, user_high_id) do update
    set active = true,
      version = public.friendships.version + 1,
      last_operation_id = excluded.last_operation_id;
  end if;

  insert into public.friendship_operations (
    actor_user_id, operation_id, operation_kind, operation_target
  ) values (actor_id, p_operation_id, p_transition, operation_target);
  return private.friendship_snapshot_for(actor_id);
end;
$$;

create or replace function public.remove_friendship(
  p_friend_id uuid,
  p_operation_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.friendship_actor();
  relation_row public.friendships%rowtype;
  existing_kind text;
  existing_target text;
  low_id uuid := least(actor_id, p_friend_id);
  high_id uuid := greatest(actor_id, p_friend_id);
  operation_target text := 'friend:' || p_friend_id::text
    || ':version:' || p_expected_version::text;
begin
  if p_friend_id is null
    or p_friend_id = actor_id
    or p_operation_id is null
    or p_expected_version is null
    or p_expected_version < 1
  then
    raise exception 'friendship_unavailable';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(actor_id::text || ':' || p_operation_id::text, 0)
  );
  select operation_kind, friendship_operations.operation_target
  into existing_kind, existing_target
  from public.friendship_operations
  where actor_user_id = actor_id and operation_id = p_operation_id;
  if existing_kind is not null then
    if existing_kind <> 'remove' or existing_target <> operation_target then
      raise exception 'friendship_conflict';
    end if;
    return private.friendship_snapshot_for(actor_id);
  end if;

  select * into relation_row
  from public.friendships
  where user_low_id = low_id and user_high_id = high_id and active
  for update;
  if relation_row.user_low_id is null then raise exception 'friendship_unavailable'; end if;
  if relation_row.version <> p_expected_version then raise exception 'friendship_conflict'; end if;

  update public.friendships
  set active = false,
    version = version + 1,
    last_operation_id = p_operation_id
  where user_low_id = low_id and user_high_id = high_id;
  insert into public.friendship_operations (
    actor_user_id, operation_id, operation_kind, operation_target
  ) values (actor_id, p_operation_id, 'remove', operation_target);
  return private.friendship_snapshot_for(actor_id);
end;
$$;

revoke all on function public.friendship_snapshot() from public;
revoke all on function public.rotate_friend_invite_code(text, text, timestamptz) from public;
revoke all on function public.ensure_friend_invite_code(text, text, timestamptz) from public;
revoke all on function public.resolve_friend_invite_code(text) from public;
revoke all on function public.send_friend_request(text, uuid) from public;
revoke all on function public.transition_friend_request(uuid, text, uuid, integer) from public;
revoke all on function public.remove_friendship(uuid, uuid, integer) from public;

grant execute on function public.friendship_snapshot() to authenticated;
grant execute on function public.rotate_friend_invite_code(text, text, timestamptz) to authenticated;
grant execute on function public.ensure_friend_invite_code(text, text, timestamptz) to authenticated;
grant execute on function public.resolve_friend_invite_code(text) to authenticated;
grant execute on function public.send_friend_request(text, uuid) to authenticated;
grant execute on function public.transition_friend_request(uuid, text, uuid, integer) to authenticated;
grant execute on function public.remove_friendship(uuid, uuid, integer) to authenticated;

comment on table public.friend_invite_codes is
  'Owner-visible expiring invite codes. Mutations are exposed only through authenticated RPCs.';
comment on table public.friendship_requests is
  'Directional friendship requests with optimistic versions and terminal history.';
comment on table public.friendships is
  'One unordered accepted friendship row per user pair.';
comment on table public.friendship_operations is
  'Per-actor idempotency ledger for friendship mutations, including deleted relations.';
