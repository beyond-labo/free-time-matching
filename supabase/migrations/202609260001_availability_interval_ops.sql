-- himatch: destructive-migration-reviewed
-- The DELETE statements below run only inside authenticated interval operations to
-- replace an owner's merged slots or subtract the owner's selected time. Applying
-- this migration does not delete existing rows or perform a schema contraction.
create table private.availability_interval_operations (
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  operation_kind text not null check (operation_kind in ('union', 'subtract')),
  operation_id uuid not null,
  payload jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (owner_user_id, operation_kind, operation_id)
);

revoke all on private.availability_interval_operations from public, anon, authenticated;

-- The older table CHECK casts epoch seconds to bigint, which can round a
-- fractional second onto a quarter-hour. Keep existing rows untouched while
-- enforcing exact boundaries for every new or updated slot, including legacy APIs.
create or replace function private.validate_availability_window()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.start_at < now() or new.end_at > now() + interval '14 days'
     or mod(extract(epoch from new.start_at), 900) <> 0
     or mod(extract(epoch from new.end_at), 900) <> 0 then
    raise exception using errcode = '23514', message = 'availability_invalid';
  end if;
  return new;
end;
$$;

create or replace function public.availability_union_interval(
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_category text,
  p_visibility text,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  request_payload jsonb;
  saved_payload jsonb;
  saved_result jsonb;
  merged_start timestamptz;
  merged_end timestamptz;
  next_start timestamptz;
  next_end timestamptz;
  keep_id uuid;
  result_value jsonb;
begin
  if actor_id is null or not public.is_account_active() then
    raise exception using errcode = '42501', message = 'availability_invalid';
  end if;
  if p_operation_id is null or p_start_at is null or p_end_at is null
     or p_start_at >= p_end_at
     or extract(epoch from p_start_at) - floor(extract(epoch from p_start_at) / 900) * 900 <> 0
     or extract(epoch from p_end_at) - floor(extract(epoch from p_end_at) / 900) * 900 <> 0
     or p_visibility is null
     or p_category is not null and p_category not in ('game', 'meal', 'call', 'work')
     or p_visibility not in ('privateUntilAccepted', 'shareOnHosting') then
    raise exception using errcode = '23514', message = 'availability_invalid';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(actor_id::text, 0));
  request_payload := jsonb_build_object('start_at', p_start_at, 'end_at', p_end_at, 'category', p_category, 'visibility', p_visibility);
  select payload, result into saved_payload, saved_result
  from private.availability_interval_operations
  where owner_user_id = actor_id and operation_kind = 'union' and operation_id = p_operation_id;
  if found then
    if saved_payload <> request_payload then
      raise exception using errcode = '23505', message = 'availability_operation_conflict';
    end if;
    return saved_result;
  end if;
  if p_start_at < now() or p_end_at > now() + interval '14 days' then
    raise exception using errcode = '23514', message = 'availability_invalid';
  end if;

  merged_start := p_start_at;
  merged_end := p_end_at;
  loop
    select min(start_at), max(end_at)
    into next_start, next_end
    from public.availability_slots
    where owner_user_id = actor_id and start_at <= merged_end and end_at >= merged_start;
    exit when next_start is null
      or (least(merged_start, next_start) = merged_start and greatest(merged_end, next_end) = merged_end);
    merged_start := least(merged_start, next_start);
    merged_end := greatest(merged_end, next_end);
  end loop;
  select (array_agg(id order by created_at, id))[1]
  into keep_id
  from public.availability_slots
  where owner_user_id = actor_id and start_at <= merged_end and end_at >= merged_start;
  if keep_id is null then keep_id := gen_random_uuid(); end if;

  delete from public.availability_slots
  where owner_user_id = actor_id and start_at <= merged_end and end_at >= merged_start;
  insert into public.availability_slots (id, owner_user_id, start_at, end_at, category, visibility)
  values (keep_id, actor_id, merged_start, merged_end, p_category, p_visibility);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'start_at', start_at, 'end_at', end_at, 'category', category, 'visibility', visibility
  ) order by start_at, id), '[]'::jsonb)
  into result_value from public.availability_slots where owner_user_id = actor_id;
  insert into private.availability_interval_operations(owner_user_id, operation_kind, operation_id, payload, result)
  values (actor_id, 'union', p_operation_id, request_payload, result_value);
  return result_value;
end;
$$;

create or replace function public.availability_subtract_interval(
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  request_payload jsonb;
  saved_payload jsonb;
  saved_result jsonb;
  slot_row record;
  right_id uuid;
  result_value jsonb;
begin
  if actor_id is null or not public.is_account_active() then
    raise exception using errcode = '42501', message = 'availability_invalid';
  end if;
  if p_operation_id is null or p_start_at is null or p_end_at is null
     or p_start_at >= p_end_at
     or extract(epoch from p_start_at) - floor(extract(epoch from p_start_at) / 900) * 900 <> 0
     or extract(epoch from p_end_at) - floor(extract(epoch from p_end_at) / 900) * 900 <> 0 then
    raise exception using errcode = '23514', message = 'availability_invalid';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(actor_id::text, 0));
  request_payload := jsonb_build_object('start_at', p_start_at, 'end_at', p_end_at);
  select payload, result into saved_payload, saved_result
  from private.availability_interval_operations
  where owner_user_id = actor_id and operation_kind = 'subtract' and operation_id = p_operation_id;
  if found then
    if saved_payload <> request_payload then
      raise exception using errcode = '23505', message = 'availability_operation_conflict';
    end if;
    return saved_result;
  end if;
  if p_start_at < now() or p_end_at > now() + interval '14 days' then
    raise exception using errcode = '23514', message = 'availability_invalid';
  end if;

  for slot_row in
    select id, start_at, end_at, category, visibility
    from public.availability_slots
    where owner_user_id = actor_id and start_at < p_end_at and end_at > p_start_at
    order by start_at for update
  loop
    delete from public.availability_slots where id = slot_row.id;
    if slot_row.start_at < p_start_at then
      insert into public.availability_slots (id, owner_user_id, start_at, end_at, category, visibility)
      values (slot_row.id, actor_id, slot_row.start_at, least(slot_row.end_at, p_start_at), slot_row.category, slot_row.visibility);
      if slot_row.end_at > p_end_at then
        insert into public.availability_slots (id, owner_user_id, start_at, end_at, category, visibility)
        values (gen_random_uuid(), actor_id, p_end_at, slot_row.end_at, slot_row.category, slot_row.visibility);
      end if;
    elsif slot_row.end_at > p_end_at then
      insert into public.availability_slots (id, owner_user_id, start_at, end_at, category, visibility)
      values (slot_row.id, actor_id, p_end_at, slot_row.end_at, slot_row.category, slot_row.visibility);
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'start_at', start_at, 'end_at', end_at, 'category', category, 'visibility', visibility
  ) order by start_at, id), '[]'::jsonb)
  into result_value from public.availability_slots where owner_user_id = actor_id;
  insert into private.availability_interval_operations(owner_user_id, operation_kind, operation_id, payload, result)
  values (actor_id, 'subtract', p_operation_id, request_payload, result_value);
  return result_value;
end;
$$;

revoke all on function public.availability_union_interval(timestamptz, timestamptz, text, text, uuid) from public, anon;
revoke all on function public.availability_subtract_interval(timestamptz, timestamptz, uuid) from public, anon;
grant execute on function public.availability_union_interval(timestamptz, timestamptz, text, text, uuid) to authenticated;
grant execute on function public.availability_subtract_interval(timestamptz, timestamptz, uuid) to authenticated;
