-- himatch: destructive-migration-reviewed
-- Availability row deletes below are runtime interval subtraction or a transaction-scoped private union guard cleanup; no existing user data is dropped by this migration.
create table public.hostings (
  id uuid primary key default gen_random_uuid(),
  host_user_id uuid not null references auth.users(id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  mode text not null check (mode in ('online','offline')),
  area text check (area is null or area in ('shinjuku','shibuya','discussLater')),
  category text check (category is null or category in ('game','meal','call','work')),
  availability_category text check (availability_category is null or availability_category in ('game','meal','call','work')),
  availability_visibility text not null check (availability_visibility in ('privateUntilAccepted','shareOnHosting')),
  status text not null default 'recruiting' check (status in ('recruiting','cancelled')),
  version integer not null default 1 check (version > 0),
  last_operation_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hostings_interval_check check (end_at > start_at),
  constraint hostings_quarter_hour_check check (
    mod(extract(epoch from start_at),900)=0 and mod(extract(epoch from end_at),900)=0
  ),
  constraint hostings_mode_area_check check ((mode='online' and area is null) or (mode='offline' and area is not null))
);

create index hostings_owner_start on public.hostings(host_user_id,start_at desc);
create index hostings_active_interval on public.hostings(start_at,end_at) where status='recruiting';
create trigger hostings_set_updated_at before update on public.hostings
for each row execute function private.set_updated_at();

create table public.hosting_invitations (
  hosting_id uuid not null references public.hostings(id) on delete cascade,
  invitee_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  intervals jsonb,
  version integer not null default 1 check(version > 0),
  last_operation_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(hosting_id,invitee_user_id),
  constraint hosting_invitation_response_check check (
    (status='accepted' and jsonb_typeof(intervals)='array' and jsonb_array_length(intervals)>0)
    or (status='declined' and intervals='[]'::jsonb)
    or (status='pending' and intervals is null)
  )
);
create index hosting_invitations_invitee on public.hosting_invitations(invitee_user_id,created_at desc);

create table private.hosting_operations (
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  operation_kind text not null check(operation_kind in ('create','respond','cancel')),
  payload jsonb not null,
  hosting_id uuid not null,
  created_at timestamptz not null default now(),
  primary key(actor_user_id,operation_id)
);
revoke all on private.hosting_operations from public,anon,authenticated;

create table private.availability_union_guard (
  transaction_id bigint not null,
  owner_user_id uuid not null,
  primary key(transaction_id,owner_user_id)
);
revoke all on private.availability_union_guard from public,anon,authenticated;

alter table public.hostings enable row level security;
alter table public.hosting_invitations enable row level security;
revoke all on public.hostings,public.hosting_invitations from public,anon,authenticated;
grant select,insert,update,delete on public.hostings,public.hosting_invitations to service_role;

create policy hostings_select_participant on public.hostings for select to authenticated
using ((select auth.uid())=host_user_id or exists(select 1 from public.hosting_invitations i where i.hosting_id=id and i.invitee_user_id=(select auth.uid())));
create policy hosting_invitations_select_participant on public.hosting_invitations for select to authenticated
using ((select auth.uid())=invitee_user_id or exists(select 1 from public.hostings h where h.id=hosting_id and h.host_user_id=(select auth.uid()) and status='recruiting'));

create or replace function private.hosting_actor()
returns uuid language plpgsql stable security definer set search_path=''
as $$
declare actor uuid := auth.uid();
begin
  if actor is null or not public.is_account_active() then raise exception using errcode='42501',message='hosting_unavailable'; end if;
  return actor;
end; $$;
revoke all on function private.hosting_actor() from public,anon,authenticated;

create or replace function private.hosting_projection(p_actor uuid,p_hosting_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare h public.hostings%rowtype; result jsonb; invitation public.hosting_invitations%rowtype;
begin
  select * into h from public.hostings where id=p_hosting_id;
  if h.id is null then return null; end if;
  if h.host_user_id=p_actor then
    select jsonb_build_object(
      'id',h.id,'hostUserId',h.host_user_id,'start',h.start_at,'end',h.end_at,
      'mode',h.mode,'area',h.area,'category',h.category,
      'status',case when h.status='cancelled' then 'cancelled' when h.start_at<=now() then 'expired' else 'open' end,
      'version',h.version,'createdAt',h.created_at,
      'acceptedParticipants',coalesce((select jsonb_agg(jsonb_build_object(
        'userId',i.invitee_user_id,'nickname',p.nickname,'presetIconKey',p.preset_icon_key,
        'intervals',i.intervals
      ) order by p.nickname,i.invitee_user_id) from public.hosting_invitations i
      join public.user_profiles p on p.user_id=i.invitee_user_id
      where i.hosting_id=h.id and i.status='accepted' and private.account_is_active(i.invitee_user_id)),'[]'::jsonb)
    ) into result;
    return result;
  end if;
  select * into invitation from public.hosting_invitations i
  where i.hosting_id=h.id and i.invitee_user_id=p_actor;
  if invitation.hosting_id is null then return null; end if;
  return jsonb_build_object(
    'id',h.id,'hostUserId',h.host_user_id,'start',h.start_at,'end',h.end_at,
    'mode',h.mode,'area',h.area,'category',h.category,
    'status',case when h.status='cancelled' then 'cancelled' when h.start_at<=now() then 'expired' else 'open' end,
    'version',h.version,'createdAt',h.created_at,
    'host',(select jsonb_build_object('userId',p.user_id,'nickname',p.nickname,'presetIconKey',p.preset_icon_key)
      from public.user_profiles p where p.user_id=h.host_user_id),
    'myInvitation',jsonb_build_object('status',invitation.status,'version',invitation.version,'intervals',invitation.intervals)
  );
end; $$;
revoke all on function private.hosting_projection(uuid,uuid) from public,anon,authenticated;

create or replace function public.hosting_get(p_hosting_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare actor uuid := private.hosting_actor(); value jsonb;
begin
  if p_hosting_id is null then raise exception 'hosting_unavailable'; end if;
  value := private.hosting_projection(actor,p_hosting_id);
  if value is null then raise exception using errcode='P0002',message='hosting_unavailable'; end if;
  return value;
end; $$;

create or replace function public.hosting_snapshot()
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare actor uuid := private.hosting_actor(); value jsonb;
begin
  select coalesce(jsonb_agg(private.hosting_projection(actor,q.id) order by q.start_at), '[]'::jsonb)
  into value from (
    select distinct h.id,h.start_at from public.hostings h
    left join public.hosting_invitations i on i.hosting_id=h.id
    where h.host_user_id=actor or i.invitee_user_id=actor
  ) q;
  return value;
end; $$;

create or replace function public.hosting_create(
  p_start_at timestamptz,p_end_at timestamptz,p_mode text,p_area text,p_category text,
  p_targets jsonb,p_availability_category text,p_availability_visibility text,p_operation_id uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor uuid := private.hosting_actor(); request_payload jsonb; saved_payload jsonb;
  saved_hosting uuid; hosting_id uuid; target jsonb; target_id uuid; low_id uuid; high_id uuid;
begin
  if p_operation_id is null or p_start_at is null or p_end_at is null or p_start_at>=p_end_at
    or p_mode is null or p_mode not in ('online','offline')
    or p_targets is null or jsonb_typeof(p_targets)<>'array' or jsonb_array_length(p_targets)<1 or jsonb_array_length(p_targets)>50
    or p_availability_visibility is null
    or (p_mode='online' and p_area is not null) or (p_mode='offline' and (p_area is null or p_area not in ('shinjuku','shibuya','discussLater')))
    or p_category is not null and p_category not in ('game','meal','call','work')
    or p_availability_category is not null and p_availability_category not in ('game','meal','call','work')
    or p_availability_visibility not in ('privateUntilAccepted','shareOnHosting') then
    raise exception using errcode='23514',message='hosting_unavailable';
  end if;
  request_payload:=jsonb_build_object('start',p_start_at,'end',p_end_at,'mode',p_mode,'area',p_area,'category',p_category,
    'targets',p_targets,'availabilityCategory',p_availability_category,'availabilityVisibility',p_availability_visibility);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':hosting:'||p_operation_id::text,0));
  select o.payload,o.hosting_id into saved_payload,saved_hosting from private.hosting_operations o
    where o.actor_user_id=actor and o.operation_id=p_operation_id;
  if found then
    if saved_payload<>request_payload then raise exception using errcode='23505',message='hosting_conflict'; end if;
    return private.hosting_projection(actor,saved_hosting);
  end if;

  if p_start_at<now() or p_end_at>now()+interval '14 days'
    or mod(extract(epoch from p_start_at),900)<>0 or mod(extract(epoch from p_end_at),900)<>0 then
    raise exception using errcode='23514',message='hosting_unavailable';
  end if;

  if exists(select 1 from (select value->>'id' friend_id,count(*) n from jsonb_array_elements(p_targets) group by value->>'id') d where n>1)
    or exists(select 1 from jsonb_array_elements(p_targets) t where coalesce(t->>'type','')<>'friend' or coalesce(t->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
    raise exception using errcode='23514',message='hosting_unavailable';
  end if;
  for target in select value from jsonb_array_elements(p_targets) order by value->>'id' loop
    target_id:=(target->>'id')::uuid;
    if target_id=actor or not private.account_is_active(target_id) then raise exception using errcode='42501',message='hosting_unavailable'; end if;
    low_id:=least(actor,target_id); high_id:=greatest(actor,target_id);
    -- Serialize with remove_friendship, which locks this same relation row.
    perform 1 from public.friendships f
      where f.user_low_id=low_id and f.user_high_id=high_id and f.active for update;
    if not found then
      raise exception using errcode='42501',message='hosting_unavailable';
    end if;
  end loop;

  -- Same transaction: a failed invitation insert rolls back both the hosting and availability union.
  perform public.availability_union_interval(p_start_at,p_end_at,p_availability_category,p_availability_visibility,p_operation_id);
  insert into public.hostings(host_user_id,start_at,end_at,mode,area,category,availability_category,availability_visibility,last_operation_id)
  values(actor,p_start_at,p_end_at,p_mode,p_area,p_category,p_availability_category,p_availability_visibility,p_operation_id)
  returning id into hosting_id;
  insert into public.hosting_invitations(hosting_id,invitee_user_id)
    select hosting_id,(value->>'id')::uuid from jsonb_array_elements(p_targets);
  insert into private.hosting_operations(actor_user_id,operation_id,operation_kind,payload,hosting_id)
  values(actor,p_operation_id,'create',request_payload,hosting_id);
  return private.hosting_projection(actor,hosting_id);
end; $$;

create or replace function public.hosting_respond(
  p_hosting_id uuid,p_status text,p_intervals jsonb,p_operation_id uuid,p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor uuid := private.hosting_actor(); h public.hostings%rowtype; inv public.hosting_invitations%rowtype;
  payload jsonb; prior_payload jsonb; prior_hosting uuid; item jsonb; a timestamptz; b timestamptz; previous_end timestamptz;
begin
  if p_hosting_id is null or p_operation_id is null or p_expected_version is null or p_expected_version<1
     or p_status is null or p_status not in ('accepted','declined') or p_intervals is null or jsonb_typeof(p_intervals)<>'array' then
    raise exception using errcode='23514',message='hosting_unavailable';
  end if;
  payload:=jsonb_build_object('hostingId',p_hosting_id,'status',p_status,'intervals',p_intervals,'expectedVersion',p_expected_version);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':hosting:'||p_operation_id::text,0));
  select o.payload,o.hosting_id into prior_payload,prior_hosting from private.hosting_operations o
    where o.actor_user_id=actor and o.operation_id=p_operation_id;
  if found then
    if prior_payload<>payload or (select operation_kind from private.hosting_operations where actor_user_id=actor and operation_id=p_operation_id)<>'respond' then
      raise exception using errcode='23505',message='hosting_conflict';
    end if;
    return private.hosting_projection(actor,prior_hosting);
  end if;
  select * into h from public.hostings where id=p_hosting_id for update;
  if h.id is null or h.host_user_id=actor or h.status<>'recruiting' or h.start_at<=now() then
    raise exception using errcode='P0002',message='hosting_unavailable';
  end if;
  select * into inv from public.hosting_invitations where hosting_id=p_hosting_id and invitee_user_id=actor for update;
  if inv.hosting_id is null then raise exception using errcode='P0002',message='hosting_unavailable'; end if;
  if inv.version<>p_expected_version or inv.status<>'pending' then raise exception using errcode='40001',message='hosting_conflict'; end if;
  if (p_status='accepted' and jsonb_array_length(p_intervals)=0) or (p_status='declined' and jsonb_array_length(p_intervals)<>0) then
    raise exception using errcode='23514',message='hosting_unavailable';
  end if;
  for item in select value from jsonb_array_elements(p_intervals) with ordinality as intervals(value,ordinality) order by ordinality loop
    begin a:=(item->>'start')::timestamptz; b:=(item->>'end')::timestamptz;
    exception when others then raise exception using errcode='23514',message='hosting_unavailable'; end;
    if jsonb_typeof(item)<>'object' or a is null or b is null or a>=b or a<h.start_at or b>h.end_at
      or extract(epoch from a) - floor(extract(epoch from a) / 900) * 900 <> 0
      or extract(epoch from b) - floor(extract(epoch from b) / 900) * 900 <> 0 then
      raise exception using errcode='23514',message='hosting_unavailable';
    end if;
    if previous_end is not null and a<previous_end then raise exception using errcode='23514',message='hosting_unavailable'; end if;
    previous_end:=b;
  end loop;
  update public.hosting_invitations set status=p_status,intervals=p_intervals,version=version+1,last_operation_id=p_operation_id
    where hosting_id=p_hosting_id and invitee_user_id=actor;
  insert into private.hosting_operations(actor_user_id,operation_id,operation_kind,payload,hosting_id)
    values(actor,p_operation_id,'respond',payload,p_hosting_id);
  return private.hosting_projection(actor,p_hosting_id);
end; $$;

create or replace function public.hosting_cancel(p_hosting_id uuid,p_operation_id uuid,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor uuid := private.hosting_actor(); h public.hostings%rowtype; payload jsonb; prior_payload jsonb; prior_hosting uuid; prior_kind text;
begin
  if p_hosting_id is null or p_operation_id is null or p_expected_version is null or p_expected_version<1 then raise exception using errcode='23514',message='hosting_unavailable'; end if;
  payload:=jsonb_build_object('hostingId',p_hosting_id,'expectedVersion',p_expected_version);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':hosting:'||p_operation_id::text,0));
  select o.operation_kind,o.payload,o.hosting_id into prior_kind,prior_payload,prior_hosting from private.hosting_operations o
    where o.actor_user_id=actor and o.operation_id=p_operation_id;
  if found then
    if prior_kind<>'cancel' or prior_payload<>payload then raise exception using errcode='23505',message='hosting_conflict'; end if;
    return private.hosting_projection(actor,prior_hosting);
  end if;
  select * into h from public.hostings where id=p_hosting_id;
  if h.id is null or h.host_user_id<>actor then raise exception using errcode='P0002',message='hosting_unavailable'; end if;
  -- Serialize cancellation with every availability interval operation by the owner.
  perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
  select * into h from public.hostings where id=p_hosting_id for update;
  if h.status<>'recruiting' or h.start_at<=now() then raise exception using errcode='P0002',message='hosting_unavailable'; end if;
  if h.version<>p_expected_version then raise exception using errcode='40001',message='hosting_conflict'; end if;
  update public.hostings set status='cancelled',version=version+1,last_operation_id=p_operation_id where id=p_hosting_id;
  insert into private.hosting_operations(actor_user_id,operation_id,operation_kind,payload,hosting_id)
    values(actor,p_operation_id,'cancel',payload,p_hosting_id);
  return private.hosting_projection(actor,p_hosting_id);
end; $$;

create or replace function private.guard_hosted_availability_change()
returns trigger language plpgsql security definer set search_path=''
as $$
declare owner_id uuid; old_start timestamptz; old_end timestamptz; new_start timestamptz; new_end timestamptz;
begin
  owner_id:=old.owner_user_id; old_start:=old.start_at; old_end:=old.end_at;
  if tg_op='UPDATE' then new_start:=new.start_at; new_end:=new.end_at; end if;
  if exists(select 1 from private.availability_union_guard g where g.transaction_id=txid_current() and g.owner_user_id=owner_id) then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  if private.account_is_active(owner_id) and exists(select 1 from public.hostings h where h.host_user_id=owner_id and h.status='recruiting'
    and h.start_at>now() and h.start_at<old_end and h.end_at>old_start
    and (tg_op='DELETE' or new_start is distinct from old_start or new_end is distinct from old_end)) then
    raise exception using errcode='23P01',message='availability_hosting_conflict';
  end if;
  if tg_op='UPDATE' and private.account_is_active(owner_id) and exists(select 1 from public.hostings h where h.host_user_id=owner_id and h.status='recruiting'
    and h.start_at>now() and h.start_at<new_end and h.end_at>new_start) then
    raise exception using errcode='23P01',message='availability_hosting_conflict';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end; $$;
revoke all on function private.guard_hosted_availability_change() from public,anon,authenticated;
create trigger availability_hosting_delete_guard before delete on public.availability_slots
for each row execute function private.guard_hosted_availability_change();
create trigger availability_hosting_update_guard before update of start_at,end_at on public.availability_slots
for each row execute function private.guard_hosted_availability_change();

-- The union RPC only expands intervals. Permit its delete/reinsert implementation while
-- retaining the protected candidate in the final merged row; direct ID deletes remain blocked.
alter function public.availability_union_interval(timestamptz,timestamptz,text,text,uuid)
  rename to availability_union_interval_unchecked;
revoke all on function public.availability_union_interval_unchecked(timestamptz,timestamptz,text,text,uuid) from public,anon,authenticated;
create or replace function public.availability_union_interval(
  p_start_at timestamptz,p_end_at timestamptz,p_category text,p_visibility text,p_operation_id uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor uuid := auth.uid(); result_value jsonb;
begin
  if actor is null then raise exception using errcode='42501',message='availability_invalid'; end if;
  insert into private.availability_union_guard(transaction_id,owner_user_id) values(txid_current(),actor);
  result_value:=public.availability_union_interval_unchecked(p_start_at,p_end_at,p_category,p_visibility,p_operation_id);
  delete from private.availability_union_guard where transaction_id=txid_current() and owner_user_id=actor;
  return result_value;
end; $$;
revoke all on function public.availability_union_interval(timestamptz,timestamptz,text,text,uuid) from public,anon;
grant execute on function public.availability_union_interval(timestamptz,timestamptz,text,text,uuid) to authenticated;

revoke all on function public.hosting_get(uuid) from public,anon;
revoke all on function public.hosting_snapshot() from public,anon;
revoke all on function public.hosting_create(timestamptz,timestamptz,text,text,text,jsonb,text,text,uuid) from public,anon;
revoke all on function public.hosting_respond(uuid,text,jsonb,uuid,integer) from public,anon;
revoke all on function public.hosting_cancel(uuid,uuid,integer) from public,anon;
grant execute on function public.hosting_get(uuid) to authenticated;
grant execute on function public.hosting_snapshot() to authenticated;
grant execute on function public.hosting_create(timestamptz,timestamptz,text,text,text,jsonb,text,text,uuid) to authenticated;
grant execute on function public.hosting_respond(uuid,text,jsonb,uuid,integer) to authenticated;
grant execute on function public.hosting_cancel(uuid,uuid,integer) to authenticated;
