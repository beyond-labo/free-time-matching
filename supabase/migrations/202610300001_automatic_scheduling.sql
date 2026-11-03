-- himatch: destructive-migration-reviewed
-- Additive schema. Runtime DELETEs only invalidate permissions and delivery tokens;
-- no pre-existing user data is removed by applying this migration.
create table private.scheduling_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false
);
create table private.scheduling_permissions (
  user_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  primary key(user_id,friend_id), check(user_id<>friend_id)
);
create table private.scheduling_blocks (
  user_id uuid not null references auth.users(id) on delete cascade,
  blocked_user_id uuid not null references auth.users(id) on delete cascade,
  primary key(user_id,blocked_user_id), check(user_id<>blocked_user_id)
);
create table private.scheduling_proposals (
  id uuid primary key default gen_random_uuid(),
  user_low_id uuid references auth.users(id) on delete set null,
  user_high_id uuid references auth.users(id) on delete set null,
  start_at timestamptz not null, end_at timestamptz not null,
  status text not null default 'pending' check(status in ('pending','confirmed','declined','expired','cancelled')),
  created_at timestamptz not null default clock_timestamp(), confirmed_at timestamptz,
  check(user_low_id<user_high_id),
  check(end_at>=start_at+interval '15 minutes' and end_at<=start_at+interval '24 hours'),
  check(mod(extract(epoch from start_at),900)=0 and mod(extract(epoch from end_at),900)=0)
);
create index scheduling_proposals_participants on private.scheduling_proposals(user_low_id,user_high_id,created_at desc);
create table private.scheduling_responses (
  proposal_id uuid not null references private.scheduling_proposals(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  response text not null default 'pending' check(response in ('pending','accepted','declined')),
  share_acceptance boolean not null default false,
  version integer not null default 1 check(version>=1),
  primary key(proposal_id,user_id)
);
-- A recipient's count survives the other participant's account deletion. This
-- receipt contains neither the peer nor a candidate time and is not exposed.
create table private.scheduling_receipts (
  user_id uuid not null references auth.users(id) on delete cascade,
  proposal_id uuid not null references private.scheduling_proposals(id),
  created_at timestamptz not null default clock_timestamp(), primary key(user_id,proposal_id)
);
create index scheduling_receipts_recent on private.scheduling_receipts(user_id,created_at desc);
create table private.scheduling_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null, kind text not null, payload jsonb not null,
  primary key(user_id,operation_id)
);
create table private.scheduling_feedback (
  proposal_id uuid not null references private.scheduling_proposals(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  played boolean not null, bothersome boolean not null, privacy_concern boolean not null,
  primary key(proposal_id,user_id)
);
create table private.scheduling_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  target_user_id uuid references auth.users(id) on delete set null,
  proposal_id uuid references private.scheduling_proposals(id),
  reason text not null check(reason in ('spam','harassment','other')),
  created_at timestamptz not null default clock_timestamp(),
  unique(reporter_id,operation_id)
);
create table private.scheduling_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  proposal_id uuid not null references private.scheduling_proposals(id),
  kind text not null check(kind in ('proposal','confirmed','cancelled')),
  created_at timestamptz not null default clock_timestamp(), unique(user_id,proposal_id,kind)
);
create table private.scheduling_devices (
  token text primary key check(token ~ '^[0-9a-f]{64}$'),
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null check(environment in ('sandbox','production')),
  enabled boolean not null default true
);
create table private.scheduling_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references private.scheduling_notifications(id) on delete cascade,
  token text not null,
  environment text not null check(environment in ('sandbox','production')),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','leased','sent','stopped')),
  lease_until timestamptz,
  unique(notification_id,token)
);
revoke all on private.scheduling_settings,private.scheduling_permissions,private.scheduling_blocks,
 private.scheduling_proposals,private.scheduling_responses,private.scheduling_receipts,
 private.scheduling_operations,private.scheduling_feedback,private.scheduling_reports,
 private.scheduling_notifications,private.scheduling_devices,private.scheduling_deliveries
 from public,anon,authenticated;

create function private.scheduling_lock() returns void language sql volatile security definer set search_path=''
as $$ select pg_catalog.pg_advisory_xact_lock(741903,1); $$;
create function private.scheduling_actor() returns uuid language plpgsql volatile security definer set search_path=''
as $$ declare actor uuid:=auth.uid(); begin
 perform private.scheduling_lock();
 if actor is null or not private.account_is_active(actor)
   or not exists(select 1 from public.user_profiles where user_id=actor) then
   raise exception using errcode='42501',message='scheduling_unavailable';
 end if;
 perform private.scheduling_refresh();
 return actor;
end; $$;
create function private.scheduling_replay(p_actor uuid,p_operation uuid,p_kind text,p_payload jsonb)
returns boolean language plpgsql security definer set search_path=''
as $$ declare saved private.scheduling_operations%rowtype;
  request_hash jsonb:=jsonb_build_object('sha256',encode(extensions.digest(convert_to(p_payload::text,'UTF8'),'sha256'),'hex'));
begin
 if p_operation is null then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 select * into saved from private.scheduling_operations where user_id=p_actor and operation_id=p_operation;
 if found then
   if saved.kind<>p_kind or saved.payload<>request_hash then raise exception using errcode='23505',message='scheduling_conflict'; end if;
   return true;
 end if;
 -- Replay compares canonical input identity without retaining another user's
 -- UUID or response payload after that user deletes their account.
 insert into private.scheduling_operations(user_id,operation_id,kind,payload) values(p_actor,p_operation,p_kind,request_hash);
 return false;
end; $$;
create function private.scheduling_blocked(p_a uuid,p_b uuid) returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from private.scheduling_blocks b where (b.user_id=p_a and b.blocked_user_id=p_b) or (b.user_id=p_b and b.blocked_user_id=p_a)); $$;
create function private.scheduling_eligible(p_a uuid,p_b uuid) returns boolean language sql stable security definer set search_path=''
as $$ select p_a is not null and p_b is not null
 and private.account_is_active(p_a) and private.account_is_active(p_b)
 and exists(select 1 from public.user_profiles where user_id=p_a)
 and exists(select 1 from public.user_profiles where user_id=p_b)
 and not private.scheduling_blocked(p_a,p_b)
 and exists(select 1 from public.friendships where user_low_id=least(p_a,p_b) and user_high_id=greatest(p_a,p_b) and active)
 and exists(select 1 from private.scheduling_settings where user_id=p_a and enabled)
 and exists(select 1 from private.scheduling_settings where user_id=p_b and enabled)
 and exists(select 1 from private.scheduling_permissions where user_id=p_a and friend_id=p_b and enabled)
 and exists(select 1 from private.scheduling_permissions where user_id=p_b and friend_id=p_a and enabled); $$;
create function private.scheduling_has_time(p_user uuid,p_start timestamptz,p_end timestamptz) returns boolean language sql stable security definer set search_path=''
as $$ select coalesce(range_agg(tstzrange(start_at,end_at,'[)')) @> tstzrange(p_start,p_end,'[)'),false)
 from public.availability_slots where owner_user_id=p_user; $$;
create function private.scheduling_notify(p_id uuid,p_kind text) returns void language plpgsql security definer set search_path=''
as $$ begin
 with added as (
 insert into private.scheduling_notifications(user_id,proposal_id,kind)
 select r.user_id,p_id,p_kind from private.scheduling_responses r
 where r.proposal_id=p_id and private.account_is_active(r.user_id)
 on conflict do nothing returning id,user_id
 ) insert into private.scheduling_deliveries(notification_id,token,environment,recipient_id)
 select a.id,d.token,d.environment,a.user_id from added a join private.scheduling_devices d on d.user_id=a.user_id and d.enabled;
end; $$;

create function private.scheduling_refresh() returns void language plpgsql security definer set search_path=''
as $$ declare item record; next_status text; begin
 for item in select * from private.scheduling_proposals where status in ('pending','confirmed') order by id loop
   next_status:=item.status;
   if item.status='pending' then
     if item.start_at<=clock_timestamp() then next_status:='expired';
     elsif not private.scheduling_eligible(item.user_low_id,item.user_high_id)
       or not private.scheduling_has_time(item.user_low_id,item.start_at,item.end_at)
       or not private.scheduling_has_time(item.user_high_id,item.start_at,item.end_at)
       or exists(select 1 from private.scheduling_proposals other where other.id<>item.id and other.status='confirmed'
         and (other.user_low_id in (item.user_low_id,item.user_high_id) or other.user_high_id in (item.user_low_id,item.user_high_id))
         and other.start_at<item.end_at and other.end_at>item.start_at)
     then next_status:='cancelled'; end if;
   elsif item.end_at>clock_timestamp() and (item.user_low_id is null or item.user_high_id is null
     or not private.account_is_active(item.user_low_id) or not private.account_is_active(item.user_high_id)
     or private.scheduling_blocked(item.user_low_id,item.user_high_id)) then next_status:='cancelled';
   end if;
   if next_status<>item.status then
     update private.scheduling_proposals set status=next_status where id=item.id;
     if next_status='cancelled' then perform private.scheduling_notify(item.id,'cancelled'); end if;
   end if;
 end loop;
end; $$;

create function private.scheduling_generate() returns integer language plpgsql security definer set search_path=''
as $$ declare pair record; a_free tstzmultirange; b_free tstzmultirange; span tstzrange;
  proposal uuid; chosen_start timestamptz; chosen_end timestamptz; created integer:=0;
  window_start timestamptz; decision_time timestamptz;
begin
 perform private.scheduling_lock();
 decision_time:=clock_timestamp();
 window_start:=to_timestamp(ceil(extract(epoch from decision_time)/900)*900);
 perform private.scheduling_refresh();
 for pair in select user_low_id a,user_high_id b from public.friendships where active order by user_low_id,user_high_id loop
   if not private.scheduling_eligible(pair.a,pair.b)
     or exists(select 1 from private.scheduling_receipts where user_id in (pair.a,pair.b) and created_at>decision_time-interval '168 hours')
     or exists(select 1 from private.scheduling_proposals where user_low_id=pair.a and user_high_id=pair.b and created_at>decision_time-interval '336 hours')
     or exists(select 1 from private.scheduling_proposals where status='pending' and (user_low_id in (pair.a,pair.b) or user_high_id in (pair.a,pair.b)))
   then continue; end if;
   select coalesce(range_agg(tstzrange(start_at,end_at,'[)')),'{}'::tstzmultirange)
   into a_free from public.availability_slots where owner_user_id=pair.a;
   select a_free-coalesce(range_agg(tstzrange(start_at,end_at,'[)')),'{}'::tstzmultirange)
   into a_free from private.scheduling_proposals where status='confirmed' and pair.a in (user_low_id,user_high_id);
   select coalesce(range_agg(tstzrange(start_at,end_at,'[)')),'{}'::tstzmultirange)
   into b_free from public.availability_slots where owner_user_id=pair.b;
   select b_free-coalesce(range_agg(tstzrange(start_at,end_at,'[)')),'{}'::tstzmultirange)
   into b_free from private.scheduling_proposals where status='confirmed' and pair.b in (user_low_id,user_high_id);
   select segment into span from unnest(a_free*b_free*tstzmultirange(tstzrange(window_start,decision_time+interval '336 hours','[)'))) segment
   where upper(segment)-lower(segment)>=interval '15 minutes' order by lower(segment) limit 1;
   if span is null then continue; end if;
   chosen_start:=lower(span); chosen_end:=least(upper(span),chosen_start+interval '24 hours');
   insert into private.scheduling_proposals(user_low_id,user_high_id,start_at,end_at,created_at)
   values(pair.a,pair.b,chosen_start,chosen_end,decision_time) returning id into proposal;
   insert into private.scheduling_responses(proposal_id,user_id) values(proposal,pair.a),(proposal,pair.b);
   insert into private.scheduling_receipts(user_id,proposal_id,created_at) values(pair.a,proposal,decision_time),(pair.b,proposal,decision_time);
   perform private.scheduling_notify(proposal,'proposal'); created:=created+1;
 end loop;
 return created;
end; $$;

create function private.scheduling_snapshot(p_actor uuid) returns jsonb language sql stable security definer set search_path=''
as $$ select jsonb_build_object(
 'enabled',coalesce((select enabled from private.scheduling_settings where user_id=p_actor),false),
 'permissions',coalesce((select jsonb_agg(jsonb_build_object('friendId',f.friend_id,'enabled',coalesce(p.enabled,false)) order by f.friend_id)
   from (select case when user_low_id=p_actor then user_high_id else user_low_id end friend_id
     from public.friendships where p_actor in (user_low_id,user_high_id) and active) f
   left join private.scheduling_permissions p on p.user_id=p_actor and p.friend_id=f.friend_id
   where private.account_is_active(f.friend_id) and not private.scheduling_blocked(p_actor,f.friend_id)),'[]'::jsonb),
 'proposals',coalesce((select jsonb_agg(q.value order by q.start_at desc,q.id) from (
   select h.start_at,h.id,jsonb_build_object('id',h.id,'start',h.start_at,'end',h.end_at,'status',h.status,
     'myResponse',mine.response,'version',mine.version,'shareAcceptance',mine.share_acceptance)
     || case when (h.status='confirmed' or (h.status='pending' and peer.response='accepted' and peer.share_acceptance))
       and peer.user_id is not null and private.account_is_active(peer.user_id)
       and exists(select 1 from public.user_profiles u where u.user_id=peer.user_id)
       then jsonb_build_object('peer',(select jsonb_build_object('userId',u.user_id,'nickname',u.nickname,'presetIconKey',u.preset_icon_key)
         from public.user_profiles u where u.user_id=peer.user_id),'peerResponse','accepted') else '{}'::jsonb end
     || coalesce((select jsonb_build_object('feedback',jsonb_build_object('played',f.played,'bothersome',f.bothersome,'privacyConcern',f.privacy_concern))
       from private.scheduling_feedback f where f.user_id=p_actor and f.proposal_id=h.id),'{}'::jsonb) value
   from private.scheduling_proposals h join private.scheduling_responses mine on mine.proposal_id=h.id and mine.user_id=p_actor
   left join private.scheduling_responses peer on peer.proposal_id=h.id and peer.user_id<>p_actor
   order by h.start_at desc,h.id limit 200) q),'[]'::jsonb),
 'notifications',coalesce((select jsonb_agg(q.value order by q.created_at desc,q.id) from (
   select id,created_at,jsonb_build_object('id',id,'proposalId',proposal_id,'kind',kind,'createdAt',created_at) value
   from private.scheduling_notifications where user_id=p_actor order by created_at desc,id limit 200) q),'[]'::jsonb)
 ); $$;

create function public.automatic_scheduling_snapshot() returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); begin
 perform private.scheduling_refresh(); return private.scheduling_snapshot(actor);
end; $$;
create function public.automatic_scheduling_tick() returns integer language plpgsql security definer set search_path=''
as $$ begin
 if coalesce(auth.role(),'')<>'service_role' and session_user<>'postgres' then raise exception using errcode='42501',message='scheduling_unavailable'; end if;
 return private.scheduling_generate();
end; $$;

create function public.automatic_scheduling_settings(p_enabled boolean,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); begin
 if p_enabled is null then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 if not private.scheduling_replay(actor,p_operation_id,'settings',jsonb_build_object('enabled',p_enabled)) then
   insert into private.scheduling_settings(user_id,enabled) values(actor,p_enabled) on conflict(user_id) do update set enabled=excluded.enabled;
 end if;
 perform private.scheduling_generate(); return private.scheduling_snapshot(actor);
end; $$;
create function public.automatic_scheduling_permission(p_friend_id uuid,p_enabled boolean,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); begin
 if p_friend_id is null or p_enabled is null then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 if not private.scheduling_replay(actor,p_operation_id,'permission',jsonb_build_object('friendId',p_friend_id,'enabled',p_enabled)) then
   if not exists(select 1 from public.friendships where user_low_id=least(actor,p_friend_id) and user_high_id=greatest(actor,p_friend_id) and active)
     or private.scheduling_blocked(actor,p_friend_id) or not private.account_is_active(p_friend_id) then
     raise exception using errcode='P0002',message='scheduling_unavailable';
   end if;
   insert into private.scheduling_permissions(user_id,friend_id,enabled) values(actor,p_friend_id,p_enabled)
   on conflict(user_id,friend_id) do update set enabled=excluded.enabled;
 end if;
 perform private.scheduling_generate(); return private.scheduling_snapshot(actor);
end; $$;

create function public.automatic_scheduling_respond(p_proposal_id uuid,p_response text,p_share_acceptance boolean,p_operation_id uuid,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); proposal private.scheduling_proposals%rowtype; mine private.scheduling_responses%rowtype; begin
 if p_proposal_id is null or p_response is null or p_response not in ('accepted','declined') or p_share_acceptance is null
   or p_expected_version is null or p_expected_version<1 then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 perform private.scheduling_refresh();
 if not private.scheduling_replay(actor,p_operation_id,'respond',jsonb_build_object('id',p_proposal_id,'response',p_response,'shareAcceptance',p_share_acceptance,'version',p_expected_version)) then
   select * into proposal from private.scheduling_proposals where id=p_proposal_id;
   select * into mine from private.scheduling_responses where proposal_id=p_proposal_id and user_id=actor;
   if mine.user_id is null then raise exception using errcode='P0002',message='scheduling_unavailable'; end if;
   if proposal.status<>'pending' or proposal.start_at<=clock_timestamp() or mine.response<>'pending' or mine.version<>p_expected_version then raise exception using errcode='40001',message='scheduling_conflict'; end if;
   update private.scheduling_responses set response=p_response,share_acceptance=(p_response='accepted' and p_share_acceptance),version=version+1
   where proposal_id=p_proposal_id and user_id=actor;
   if p_response='declined' then update private.scheduling_proposals set status='declined' where id=p_proposal_id;
   elsif (select count(*) from private.scheduling_responses where proposal_id=p_proposal_id and response='accepted')=2 then
     -- refresh above verifies permissions, account, friendship, time, and conflicts
     -- while the common scheduling lock excludes every related writer.
     update private.scheduling_proposals set status='confirmed',confirmed_at=clock_timestamp() where id=p_proposal_id;
     perform private.scheduling_notify(p_proposal_id,'confirmed');
   end if;
 end if;
 return private.scheduling_snapshot(actor);
end; $$;

create function public.automatic_scheduling_cancel(p_proposal_id uuid,p_operation_id uuid,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); proposal private.scheduling_proposals%rowtype; mine private.scheduling_responses%rowtype; begin
 if p_proposal_id is null or p_expected_version is null or p_expected_version<1 then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 perform private.scheduling_refresh();
 if not private.scheduling_replay(actor,p_operation_id,'cancel',jsonb_build_object('id',p_proposal_id,'version',p_expected_version)) then
   select * into proposal from private.scheduling_proposals where id=p_proposal_id;
   select * into mine from private.scheduling_responses where proposal_id=p_proposal_id and user_id=actor;
   if mine.user_id is null then raise exception using errcode='P0002',message='scheduling_unavailable'; end if;
   if proposal.status not in ('pending','confirmed') or proposal.end_at<=clock_timestamp() or mine.version<>p_expected_version then
     raise exception using errcode='40001',message='scheduling_conflict';
   end if;
   update private.scheduling_proposals set status='cancelled' where id=p_proposal_id;
   update private.scheduling_responses set version=version+1 where proposal_id=p_proposal_id and user_id=actor;
   perform private.scheduling_notify(p_proposal_id,'cancelled');
 end if;
 return private.scheduling_snapshot(actor);
end; $$;

create function public.automatic_scheduling_feedback(p_proposal_id uuid,p_played boolean,p_bothersome boolean,p_privacy_concern boolean,p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); proposal private.scheduling_proposals%rowtype; begin
 if p_proposal_id is null or p_played is null or p_bothersome is null or p_privacy_concern is null then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 perform private.scheduling_refresh();
 if not private.scheduling_replay(actor,p_operation_id,'feedback',jsonb_build_object('id',p_proposal_id,'played',p_played,'bothersome',p_bothersome,'privacyConcern',p_privacy_concern)) then
   if not exists(select 1 from private.scheduling_responses where proposal_id=p_proposal_id and user_id=actor) then raise exception using errcode='P0002',message='scheduling_unavailable'; end if;
   select * into proposal from private.scheduling_proposals where id=p_proposal_id;
   if proposal.status='pending' or (proposal.status='confirmed' and proposal.end_at>clock_timestamp())
     or (p_played and (proposal.confirmed_at is null or proposal.end_at>clock_timestamp())) then raise exception using errcode='23514',message='scheduling_invalid'; end if;
   insert into private.scheduling_feedback(proposal_id,user_id,played,bothersome,privacy_concern)
   values(p_proposal_id,actor,p_played,p_bothersome,p_privacy_concern)
   on conflict(proposal_id,user_id) do update set played=excluded.played,bothersome=excluded.bothersome,privacy_concern=excluded.privacy_concern;
 end if;
 return private.scheduling_snapshot(actor);
end; $$;

create function private.scheduling_related(p_actor uuid,p_other uuid) returns boolean language sql stable security definer set search_path=''
as $$ select p_other is not null and p_actor<>p_other and (
 exists(select 1 from public.friendships where user_low_id=least(p_actor,p_other) and user_high_id=greatest(p_actor,p_other) and active)
 or exists(select 1 from private.scheduling_proposals where user_low_id=least(p_actor,p_other) and user_high_id=greatest(p_actor,p_other))
 ); $$;
-- Reporting remains available after a relationship ends and to both sides of
-- a friend request. This does not expand matching permissions or block rules.
create function private.scheduling_report_related(p_actor uuid,p_other uuid) returns boolean language sql stable security definer set search_path=''
as $$ select p_other is not null and p_actor<>p_other and (
 exists(select 1 from public.friendships where user_low_id=least(p_actor,p_other) and user_high_id=greatest(p_actor,p_other))
 or exists(select 1 from public.friendship_requests where pair_low=least(p_actor,p_other) and pair_high=greatest(p_actor,p_other))
 or exists(select 1 from private.scheduling_proposals where user_low_id=least(p_actor,p_other) and user_high_id=greatest(p_actor,p_other))
 ); $$;
create function private.scheduling_apply_block(p_actor uuid,p_other uuid) returns void language plpgsql security definer set search_path=''
as $$ begin
 if not private.scheduling_related(p_actor,p_other) and not exists(select 1 from public.friendship_requests
   where pair_low=least(p_actor,p_other) and pair_high=greatest(p_actor,p_other)) then
   raise exception using errcode='P0002',message='scheduling_unavailable';
 end if;
 insert into private.scheduling_blocks(user_id,blocked_user_id) values(p_actor,p_other) on conflict do nothing;
 update private.scheduling_permissions set enabled=false where (user_id=p_actor and friend_id=p_other) or (user_id=p_other and friend_id=p_actor);
 update public.friendships set active=false,version=version+1 where user_low_id=least(p_actor,p_other) and user_high_id=greatest(p_actor,p_other) and active;
 update public.friendship_requests set status='cancelled',version=version+1 where pair_low=least(p_actor,p_other) and pair_high=greatest(p_actor,p_other) and status='pending';
 update public.hosting_invitations i set status='declined',intervals='[]'::jsonb,version=i.version+1
 from public.hostings h where h.id=i.hosting_id and h.status='recruiting'
   and ((h.host_user_id=p_actor and i.invitee_user_id=p_other) or (h.host_user_id=p_other and i.invitee_user_id=p_actor))
   and i.status in ('pending','accepted');
 perform private.scheduling_refresh();
end; $$;
create function public.automatic_scheduling_block(p_friend_id uuid,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); begin
 if p_friend_id is null then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 if not private.scheduling_replay(actor,p_operation_id,'block',jsonb_build_object('friendId',p_friend_id)) then
   perform private.scheduling_apply_block(actor,p_friend_id);
 end if;
 return private.scheduling_snapshot(actor);
end; $$;
create function public.automatic_scheduling_block_proposal(p_proposal_id uuid,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); other_id uuid; begin
 if p_proposal_id is null then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 if not private.scheduling_replay(actor,p_operation_id,'blockProposal',jsonb_build_object('id',p_proposal_id)) then
   select case when h.user_low_id=actor then h.user_high_id else h.user_low_id end into other_id
   from private.scheduling_proposals h join private.scheduling_responses mine on mine.proposal_id=h.id and mine.user_id=actor where h.id=p_proposal_id;
   if other_id is null then raise exception using errcode='P0002',message='scheduling_unavailable'; end if;
   perform private.scheduling_apply_block(actor,other_id);
 end if;
 return private.scheduling_snapshot(actor);
end; $$;
create function public.automatic_scheduling_report(p_proposal_id uuid,p_reason text,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); other_id uuid; begin
 if p_proposal_id is null or p_reason is null or p_reason not in ('spam','harassment','other') then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 if not private.scheduling_replay(actor,p_operation_id,'report',jsonb_build_object('id',p_proposal_id,'reason',p_reason)) then
   select case when h.user_low_id=actor then h.user_high_id else h.user_low_id end into other_id
   from private.scheduling_proposals h join private.scheduling_responses mine on mine.proposal_id=h.id and mine.user_id=actor where h.id=p_proposal_id;
   if other_id is null then raise exception using errcode='P0002',message='scheduling_unavailable'; end if;
   insert into private.scheduling_reports(reporter_id,operation_id,target_user_id,proposal_id,reason) values(actor,p_operation_id,other_id,p_proposal_id,p_reason);
 end if;
 return private.scheduling_snapshot(actor);
end; $$;
create function public.automatic_scheduling_report_friend(p_friend_id uuid,p_reason text,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); begin
 if p_friend_id is null or p_reason is null or p_reason not in ('spam','harassment','other') then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 if not private.scheduling_replay(actor,p_operation_id,'reportFriend',jsonb_build_object('friendId',p_friend_id,'reason',p_reason)) then
   if not private.scheduling_report_related(actor,p_friend_id) then raise exception using errcode='P0002',message='scheduling_unavailable'; end if;
   insert into private.scheduling_reports(reporter_id,operation_id,target_user_id,reason) values(actor,p_operation_id,p_friend_id,p_reason);
 end if;
 return private.scheduling_snapshot(actor);
end; $$;

create function public.automatic_scheduling_device(p_token text,p_environment text,p_enabled boolean) returns jsonb language plpgsql security definer set search_path=''
as $$ declare actor uuid:=private.scheduling_actor(); begin
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' or p_environment is null or p_environment not in ('sandbox','production') or p_enabled is null then
   raise exception using errcode='23514',message='scheduling_invalid';
 end if;
 -- A late logout from an old session must not disable the new owner's token.
 if not p_enabled then
   update private.scheduling_devices set enabled=false where token=p_token and user_id=actor;
   update private.scheduling_deliveries set status='stopped',lease_until=null where token=p_token and recipient_id=actor and status in ('pending','leased');
   return private.scheduling_snapshot(actor);
 end if;
 -- Token ownership transfer cannot deliver the previous user's queued events.
 update private.scheduling_deliveries set status='stopped',lease_until=null where token=p_token and recipient_id<>actor and status in ('pending','leased');
 insert into private.scheduling_devices(token,user_id,environment,enabled) values(p_token,actor,p_environment,p_enabled)
 on conflict(token) do update set user_id=excluded.user_id,environment=excluded.environment,enabled=excluded.enabled;
 return private.scheduling_snapshot(actor);
end; $$;
create function public.automatic_scheduling_delivery_claim() returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 if coalesce(auth.role(),'')<>'service_role' and session_user<>'postgres' then raise exception using errcode='42501',message='scheduling_unavailable'; end if;
 perform private.scheduling_lock();
 update private.scheduling_deliveries q set status='stopped',lease_until=null
 where q.status in ('pending','leased') and (not private.account_is_active(q.recipient_id)
   or not exists(select 1 from private.scheduling_devices d where d.token=q.token and d.user_id=q.recipient_id and d.enabled and d.environment=q.environment));
 with batch as (
   select id from private.scheduling_deliveries where status='pending' or (status='leased' and lease_until<=clock_timestamp()) order by id limit 50 for update skip locked
 ), claimed as (
   update private.scheduling_deliveries q set status='leased',lease_until=clock_timestamp()+interval '5 minutes'
   from batch where q.id=batch.id returning q.id,q.token,q.environment,q.notification_id
 ) select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'token',c.token,'environment',c.environment,'kind',n.kind)),'[]'::jsonb)
 into result_value from claimed c join private.scheduling_notifications n on n.id=c.notification_id;
 return result_value;
end; $$;
create function public.automatic_scheduling_delivery_finish(p_id uuid,p_outcome text) returns void language plpgsql security definer set search_path=''
as $$ declare token_value text; begin
 if coalesce(auth.role(),'')<>'service_role' and session_user<>'postgres' then raise exception using errcode='42501',message='scheduling_unavailable'; end if;
 if p_id is null or p_outcome is null or p_outcome not in ('sent','retry','invalid_token') then raise exception using errcode='23514',message='scheduling_invalid'; end if;
 perform private.scheduling_lock();
 update private.scheduling_deliveries set status=case p_outcome when 'sent' then 'sent' when 'retry' then 'pending' else 'stopped' end,lease_until=null
 where id=p_id and status='leased' returning token into token_value;
 if p_outcome='invalid_token' and token_value is not null then
   update private.scheduling_devices set enabled=false where token=token_value;
   update private.scheduling_deliveries set status='stopped',lease_until=null where token=token_value and status in ('pending','leased');
 end if;
end; $$;

create table private.scheduling_write_guard (
 transaction_id bigint primary key, depth integer not null check(depth>0)
);
revoke all on private.scheduling_write_guard from public,anon,authenticated;
do $$ declare item record; begin
 for item in select tablename from pg_tables where schemaname='private' and tablename like 'scheduling_%' loop
   execute format('alter table private.%I enable row level security',item.tablename);
 end loop;
end; $$;
create function private.scheduling_write_begin() returns void language plpgsql security definer set search_path=''
as $$ begin
 perform private.scheduling_lock();
 insert into private.scheduling_write_guard(transaction_id,depth) values(txid_current(),1)
 on conflict(transaction_id) do update set depth=private.scheduling_write_guard.depth+1;
end; $$;
create function private.scheduling_write_end() returns void language plpgsql security definer set search_path=''
as $$ begin
 delete from private.scheduling_write_guard where transaction_id=txid_current() and depth=1;
 if not found then update private.scheduling_write_guard set depth=depth-1 where transaction_id=txid_current(); end if;
 if not exists(select 1 from private.scheduling_write_guard where transaction_id=txid_current()) then
   perform private.scheduling_generate();
 end if;
end; $$;
create function private.scheduling_lock_statement() returns trigger language plpgsql security definer set search_path=''
as $$ begin perform private.scheduling_lock(); return null; end; $$;
create function private.scheduling_changed() returns trigger language plpgsql security definer set search_path=''
as $$ begin
 if not exists(select 1 from private.scheduling_write_guard where transaction_id=txid_current()) then perform private.scheduling_generate(); end if;
 return null;
end; $$;
create function private.scheduling_friendship_changed() returns trigger language plpgsql security definer set search_path=''
as $$ begin
 if tg_op='DELETE' or not new.active then
   update private.scheduling_permissions set enabled=false
   where (user_id=old.user_low_id and friend_id=old.user_high_id) or (user_id=old.user_high_id and friend_id=old.user_low_id);
 end if;
 return null;
end; $$;
create function private.scheduling_guard_relationship() returns trigger language plpgsql security definer set search_path=''
as $$ begin
 if tg_table_name='friendships' then
   if new.active and private.scheduling_blocked(new.user_low_id,new.user_high_id) then raise exception 'friendship_unavailable'; end if;
 elsif new.status in ('pending','accepted') and private.scheduling_blocked(new.requester_id,new.addressee_id) then raise exception 'friendship_unavailable'; end if;
 return new;
end; $$;
create function private.scheduling_guard_invitation() returns trigger language plpgsql security definer set search_path=''
as $$ declare host_id uuid; begin
 if new.status in ('pending','accepted') then
   select host_user_id into host_id from public.hostings where id=new.hosting_id;
   if private.scheduling_blocked(host_id,new.invitee_user_id) then raise exception using errcode='42501',message='hosting_unavailable'; end if;
 end if;
 return new;
end; $$;
create function private.scheduling_retire(p_user uuid) returns void language plpgsql security definer set search_path=''
as $$ declare item record; begin
 update private.scheduling_settings set enabled=false where user_id=p_user;
 update private.scheduling_permissions set enabled=false where user_id=p_user or friend_id=p_user;
 update private.scheduling_devices set enabled=false where user_id=p_user;
 update private.scheduling_deliveries set status='stopped',lease_until=null where recipient_id=p_user and status in ('pending','leased');
 for item in select id from private.scheduling_proposals where p_user in (user_low_id,user_high_id)
   and (status='pending' or (status='confirmed' and end_at>clock_timestamp())) loop
   update private.scheduling_proposals set status='cancelled' where id=item.id;
   perform private.scheduling_notify(item.id,'cancelled');
 end loop;
end; $$;
create function private.scheduling_deletion_requested() returns trigger language plpgsql security definer set search_path=''
as $$ begin perform private.scheduling_retire(new.user_id); return null; end; $$;
create function private.scheduling_user_deleting() returns trigger language plpgsql security definer set search_path=''
as $$ begin perform private.scheduling_retire(old.id); return old; end; $$;

-- The common lock precedes owner/pair/row locks in all existing mutating RPCs.
-- Rename, rather than edit, old implementations to preserve their public behavior.

alter function public.availability_union_interval(timestamptz,timestamptz,text,text,uuid) rename to availability_union_interval_before_scheduling;
revoke all on function public.availability_union_interval_before_scheduling(timestamptz,timestamptz,text,text,uuid) from public,anon,authenticated,service_role;
create function public.availability_union_interval(p_start_at timestamptz,p_end_at timestamptz,p_category text,p_visibility text,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 perform private.scheduling_write_begin();
 result_value:=public.availability_union_interval_before_scheduling(p_start_at,p_end_at,p_category,p_visibility,p_operation_id);
 perform private.scheduling_write_end(); return result_value;
end; $$;
revoke all on function public.availability_union_interval(timestamptz,timestamptz,text,text,uuid) from public,anon;
grant execute on function public.availability_union_interval(timestamptz,timestamptz,text,text,uuid) to authenticated;

alter function public.availability_subtract_interval(timestamptz,timestamptz,uuid) rename to availability_subtract_interval_before_scheduling;
revoke all on function public.availability_subtract_interval_before_scheduling(timestamptz,timestamptz,uuid) from public,anon,authenticated,service_role;
create function public.availability_subtract_interval(p_start_at timestamptz,p_end_at timestamptz,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 perform private.scheduling_write_begin();
 result_value:=public.availability_subtract_interval_before_scheduling(p_start_at,p_end_at,p_operation_id);
 perform private.scheduling_write_end(); return result_value;
end; $$;
revoke all on function public.availability_subtract_interval(timestamptz,timestamptz,uuid) from public,anon;
grant execute on function public.availability_subtract_interval(timestamptz,timestamptz,uuid) to authenticated;

alter function public.hosting_create(timestamptz,timestamptz,text,text,text,jsonb,text,text,uuid) rename to hosting_create_before_scheduling;
revoke all on function public.hosting_create_before_scheduling(timestamptz,timestamptz,text,text,text,jsonb,text,text,uuid) from public,anon,authenticated,service_role;
create function public.hosting_create(p_start_at timestamptz,p_end_at timestamptz,p_mode text,p_area text,p_category text,p_targets jsonb,p_availability_category text,p_availability_visibility text,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 perform private.scheduling_write_begin();
 result_value:=public.hosting_create_before_scheduling(p_start_at,p_end_at,p_mode,p_area,p_category,p_targets,p_availability_category,p_availability_visibility,p_operation_id);
 perform private.scheduling_write_end(); return result_value;
end; $$;
revoke all on function public.hosting_create(timestamptz,timestamptz,text,text,text,jsonb,text,text,uuid) from public,anon;
grant execute on function public.hosting_create(timestamptz,timestamptz,text,text,text,jsonb,text,text,uuid) to authenticated;

alter function public.hosting_respond(uuid,text,jsonb,uuid,integer) rename to hosting_respond_before_scheduling;
revoke all on function public.hosting_respond_before_scheduling(uuid,text,jsonb,uuid,integer) from public,anon,authenticated,service_role;
create function public.hosting_respond(p_hosting_id uuid,p_status text,p_intervals jsonb,p_operation_id uuid,p_expected_version integer) returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 perform private.scheduling_write_begin();
 result_value:=public.hosting_respond_before_scheduling(p_hosting_id,p_status,p_intervals,p_operation_id,p_expected_version);
 perform private.scheduling_write_end(); return result_value;
end; $$;
revoke all on function public.hosting_respond(uuid,text,jsonb,uuid,integer) from public,anon;
grant execute on function public.hosting_respond(uuid,text,jsonb,uuid,integer) to authenticated;

alter function public.hosting_cancel(uuid,uuid,integer) rename to hosting_cancel_before_scheduling;
revoke all on function public.hosting_cancel_before_scheduling(uuid,uuid,integer) from public,anon,authenticated,service_role;
create function public.hosting_cancel(p_hosting_id uuid,p_operation_id uuid,p_expected_version integer) returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 perform private.scheduling_write_begin();
 result_value:=public.hosting_cancel_before_scheduling(p_hosting_id,p_operation_id,p_expected_version);
 perform private.scheduling_write_end(); return result_value;
end; $$;
revoke all on function public.hosting_cancel(uuid,uuid,integer) from public,anon;
grant execute on function public.hosting_cancel(uuid,uuid,integer) to authenticated;

alter function public.send_friend_request(text,uuid) rename to send_friend_request_before_scheduling;
revoke all on function public.send_friend_request_before_scheduling(text,uuid) from public,anon,authenticated,service_role;
create function public.send_friend_request(p_code_hash text,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 perform private.scheduling_write_begin();
 result_value:=public.send_friend_request_before_scheduling(p_code_hash,p_operation_id);
 perform private.scheduling_write_end(); return result_value;
end; $$;
revoke all on function public.send_friend_request(text,uuid) from public,anon;
grant execute on function public.send_friend_request(text,uuid) to authenticated;

alter function public.transition_friend_request(uuid,text,uuid,integer) rename to transition_friend_request_before_scheduling;
revoke all on function public.transition_friend_request_before_scheduling(uuid,text,uuid,integer) from public,anon,authenticated,service_role;
create function public.transition_friend_request(p_request_id uuid,p_transition text,p_operation_id uuid,p_expected_version integer) returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 perform private.scheduling_write_begin();
 result_value:=public.transition_friend_request_before_scheduling(p_request_id,p_transition,p_operation_id,p_expected_version);
 perform private.scheduling_write_end(); return result_value;
end; $$;
revoke all on function public.transition_friend_request(uuid,text,uuid,integer) from public,anon;
grant execute on function public.transition_friend_request(uuid,text,uuid,integer) to authenticated;

alter function public.remove_friendship(uuid,uuid,integer) rename to remove_friendship_before_scheduling;
revoke all on function public.remove_friendship_before_scheduling(uuid,uuid,integer) from public,anon,authenticated,service_role;
create function public.remove_friendship(p_friend_id uuid,p_operation_id uuid,p_expected_version integer) returns jsonb language plpgsql security definer set search_path=''
as $$ declare result_value jsonb; begin
 perform private.scheduling_write_begin();
 result_value:=public.remove_friendship_before_scheduling(p_friend_id,p_operation_id,p_expected_version);
 perform private.scheduling_write_end(); return result_value;
end; $$;
revoke all on function public.remove_friendship(uuid,uuid,integer) from public,anon;
grant execute on function public.remove_friendship(uuid,uuid,integer) to authenticated;

create trigger scheduling_lock_availability_slots before insert or update or delete on public.availability_slots
for each statement execute function private.scheduling_lock_statement();

create trigger scheduling_lock_friendships before insert or update or delete on public.friendships
for each statement execute function private.scheduling_lock_statement();

create trigger scheduling_lock_friendship_requests before insert or update or delete on public.friendship_requests
for each statement execute function private.scheduling_lock_statement();

create trigger scheduling_lock_hostings before insert or update or delete on public.hostings
for each statement execute function private.scheduling_lock_statement();

create trigger scheduling_lock_hosting_invitations before insert or update or delete on public.hosting_invitations
for each statement execute function private.scheduling_lock_statement();

create trigger scheduling_lock_account_deletion_requests before insert or update or delete on public.account_deletion_requests
for each statement execute function private.scheduling_lock_statement();

create trigger scheduling_changed_availability_slots after insert or update or delete on public.availability_slots
for each statement execute function private.scheduling_changed();

create trigger scheduling_changed_friendships after insert or update or delete on public.friendships
for each statement execute function private.scheduling_changed();

create trigger scheduling_lock_auth_users before delete on auth.users
for each statement execute function private.scheduling_lock_statement();
create trigger scheduling_user_deleting before delete on auth.users
for each row execute function private.scheduling_user_deleting();
create trigger scheduling_friendship_revoked after update or delete on public.friendships
for each row execute function private.scheduling_friendship_changed();
create trigger scheduling_friendship_block_guard before insert or update on public.friendships
for each row execute function private.scheduling_guard_relationship();
create trigger scheduling_request_block_guard before insert or update on public.friendship_requests
for each row execute function private.scheduling_guard_relationship();
create trigger scheduling_invitation_block_guard before insert or update on public.hosting_invitations
for each row execute function private.scheduling_guard_invitation();
create trigger scheduling_account_deletion after insert on public.account_deletion_requests
for each row execute function private.scheduling_deletion_requested();

-- Functions in private are never a client API. Explicitly remove the default
-- PUBLIC execute privilege, including the helpers called by security definers.
do $$ declare fn record; begin
 for fn in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname like 'scheduling_%' loop
   execute format('revoke all on function %s from public,anon,authenticated,service_role',fn.signature);
 end loop;
end; $$;

revoke all on function public.automatic_scheduling_snapshot() from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_snapshot() to authenticated;

revoke all on function public.automatic_scheduling_settings(boolean,uuid) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_settings(boolean,uuid) to authenticated;

revoke all on function public.automatic_scheduling_permission(uuid,boolean,uuid) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_permission(uuid,boolean,uuid) to authenticated;

revoke all on function public.automatic_scheduling_respond(uuid,text,boolean,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_respond(uuid,text,boolean,uuid,integer) to authenticated;

revoke all on function public.automatic_scheduling_cancel(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_cancel(uuid,uuid,integer) to authenticated;

revoke all on function public.automatic_scheduling_feedback(uuid,boolean,boolean,boolean,uuid) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_feedback(uuid,boolean,boolean,boolean,uuid) to authenticated;

revoke all on function public.automatic_scheduling_block(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_block(uuid,uuid) to authenticated;

revoke all on function public.automatic_scheduling_block_proposal(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_block_proposal(uuid,uuid) to authenticated;

revoke all on function public.automatic_scheduling_report(uuid,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_report(uuid,text,uuid) to authenticated;

revoke all on function public.automatic_scheduling_report_friend(uuid,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_report_friend(uuid,text,uuid) to authenticated;

revoke all on function public.automatic_scheduling_device(text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_device(text,text,boolean) to authenticated;

revoke all on function public.automatic_scheduling_tick() from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_tick() to service_role;

revoke all on function public.automatic_scheduling_delivery_claim() from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_delivery_claim() to service_role;

revoke all on function public.automatic_scheduling_delivery_finish(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.automatic_scheduling_delivery_finish(uuid,text) to service_role;
