begin;
select plan(36);

select has_table('public','hostings','hosting aggregate exists');
select has_table('public','hosting_invitations','invitation records exist separately');
select has_function('public','hosting_create',array['timestamp with time zone','timestamp with time zone','text','text','text','jsonb','text','text','uuid'],'create RPC exists');
select has_function('public','hosting_snapshot',array[]::text[],'snapshot RPC exists');
select has_function('public','hosting_get',array['uuid'],'detail RPC exists');
select has_function('public','hosting_respond',array['uuid','text','jsonb','uuid','integer'],'response RPC exists');
select has_function('public','hosting_cancel',array['uuid','uuid','integer'],'cancel RPC exists');
select has_trigger('public','availability_slots','availability_hosting_delete_guard','legacy delete is guarded by database');
select table_privs_are('public','hostings','authenticated',array[]::text[],'hosting rows are available only through privacy projection RPCs');
select table_privs_are('public','hosting_invitations','authenticated',array[]::text[],'invitation rows are not directly readable');

insert into auth.users(id) values
 ('60000000-0000-4000-8000-000000000001'),('60000000-0000-4000-8000-000000000002'),
 ('60000000-0000-4000-8000-000000000003');
insert into public.user_profiles(user_id,nickname,preset_icon_key) values
 ('60000000-0000-4000-8000-000000000001','Host','sun.max.fill'),
 ('60000000-0000-4000-8000-000000000002','Guest','figure.run'),
 ('60000000-0000-4000-8000-000000000003','Other','leaf.fill');
insert into public.friendships(user_low_id,user_high_id,last_operation_id) values
 ('60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000021'),
 ('60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000003','60000000-0000-4000-8000-000000000022');

set local role authenticated;
set local request.jwt.claim.sub='60000000-0000-4000-8000-000000000001';
select set_config('test.hosting_json',public.hosting_create(
 date_trunc('hour',now())+interval '2 hours',date_trunc('hour',now())+interval '3 hours',
 'online',null,'game', '[{"type":"friend","id":"60000000-0000-4000-8000-000000000002"},{"type":"friend","id":"60000000-0000-4000-8000-000000000003"}]'::jsonb,
 'game','privateUntilAccepted','60000000-0000-4000-8000-000000000031')::text,true);
select is(current_setting('test.hosting_json')::jsonb->>'status','open','host receives open projection');
select is((select count(*)::integer from public.availability_slots),1,'creation atomically OR-registers host availability');
select is(public.hosting_create(
 date_trunc('hour',now())+interval '2 hours',date_trunc('hour',now())+interval '3 hours',
 'online',null,'game', '[{"type":"friend","id":"60000000-0000-4000-8000-000000000002"},{"type":"friend","id":"60000000-0000-4000-8000-000000000003"}]'::jsonb,
 'game','privateUntilAccepted','60000000-0000-4000-8000-000000000031')->>'id',
 current_setting('test.hosting_json')::jsonb->>'id','create operation replay is idempotent');
select set_config('test.hosting_id',current_setting('test.hosting_json')::jsonb->>'id',true);
select is(jsonb_array_length(public.hosting_snapshot()),1,'host snapshot contains own hosting');
select ok(not ((public.hosting_get(current_setting('test.hosting_id')::uuid)) ? 'myInvitation'),'host projection omits invitee-private invitation state');
reset role;
select is((select count(*)::integer from public.hosting_invitations where hosting_id=(current_setting('test.hosting_json')::jsonb->>'id')::uuid),2,'every selected friend receives a separate invitation');
set local role authenticated;
set local request.jwt.claim.sub='60000000-0000-4000-8000-000000000001';
select throws_ok($$select public.hosting_create(date_trunc('hour',now())+interval '4 hours',date_trunc('hour',now())+interval '5 hours','online',null,null,'[{"type":"friend","id":"60000000-0000-4000-8000-000000000004"}]'::jsonb,null,'privateUntilAccepted','60000000-0000-4000-8000-000000000032')$$,'42501','hosting_unavailable','non-friend invite target is rejected');
select throws_ok($$select public.hosting_create(date_trunc('hour',now())+interval '4 hours',date_trunc('hour',now())+interval '5 hours','online',null,null,'[{"id":"60000000-0000-4000-8000-000000000002"}]'::jsonb,null,'privateUntilAccepted','60000000-0000-4000-8000-000000000035')$$,'23514','hosting_unavailable','RPC rejects a target without its type variant');
select throws_ok($$select public.hosting_create(date_trunc('hour',now())+interval '4 hours 0.5 seconds',date_trunc('hour',now())+interval '5 hours','online',null,null,'[{"type":"friend","id":"60000000-0000-4000-8000-000000000002"}]'::jsonb,null,'privateUntilAccepted','60000000-0000-4000-8000-000000000036')$$,'23514','hosting_unavailable','RPC rejects fractional-second candidate boundaries');
select throws_ok($$insert into public.availability_slots(id,owner_user_id,start_at,end_at) values ('60000000-0000-4000-8000-000000000037','60000000-0000-4000-8000-000000000001',date_trunc('hour',now())+interval '5 hours 0.5 seconds',date_trunc('hour',now())+interval '6 hours')$$,'23514','availability_invalid','legacy availability writes reject fractional-second boundaries');
select is((select count(*)::integer from public.availability_slots),1,'failed friend authorization rolls back availability changes');
select throws_ok($$delete from public.availability_slots$$,'23P01','availability_hosting_conflict','legacy availability deletion cannot erase recruiting candidate');
select throws_ok($$select public.availability_subtract_interval(date_trunc('hour',now())+interval '2 hours',date_trunc('hour',now())+interval '3 hours','60000000-0000-4000-8000-000000000033')$$,'23P01','availability_hosting_conflict','interval subtraction cannot erase recruiting candidate');
select is(jsonb_array_length(public.availability_union_interval(date_trunc('hour',now())+interval '3 hours',date_trunc('hour',now())+interval '4 hours','meal','shareOnHosting','60000000-0000-4000-8000-000000000034')),1,'adjacent union preserves an active hosting interval');

set local request.jwt.claim.sub='60000000-0000-4000-8000-000000000002';
select is(public.hosting_get(current_setting('test.hosting_id')::uuid)->'host'->>'nickname','Host','invitee sees host profile');
select is(public.hosting_get(current_setting('test.hosting_id')::uuid)->'myInvitation'->>'status','pending','invitee sees only own pending state');
select is(jsonb_array_length(public.hosting_snapshot()),1,'invitee sees addressed hosting');
select throws_ok($$select public.hosting_respond(current_setting('test.hosting_id')::uuid,'accepted',
 jsonb_build_array(jsonb_build_object('start',date_trunc('hour',now())+interval '2 hours 15 minutes 0.5 seconds','end',date_trunc('hour',now())+interval '2 hours 30 minutes')),
 '60000000-0000-4000-8000-000000000044',1)$$,'23514','hosting_unavailable','RPC rejects fractional-second answer boundaries');
select is(public.hosting_respond(current_setting('test.hosting_id')::uuid,'accepted',
 jsonb_build_array(jsonb_build_object('start',date_trunc('hour',now())+interval '2 hours 15 minutes','end',date_trunc('hour',now())+interval '2 hours 30 minutes')),
 '60000000-0000-4000-8000-000000000041',1)->'myInvitation'->>'status','accepted','invitee can accept a partial 15-minute interval');
select is(public.hosting_respond(current_setting('test.hosting_id')::uuid,'accepted',
 jsonb_build_array(jsonb_build_object('start',date_trunc('hour',now())+interval '2 hours 15 minutes','end',date_trunc('hour',now())+interval '2 hours 30 minutes')),
 '60000000-0000-4000-8000-000000000041',1)->'myInvitation'->>'status','accepted','response operation replay is idempotent');
select throws_ok($$select public.hosting_respond(current_setting('test.hosting_id')::uuid,'accepted','[]'::jsonb,'60000000-0000-4000-8000-000000000042',1)$$,'40001','hosting_conflict','stale invitation version is rejected');
set local request.jwt.claim.sub='60000000-0000-4000-8000-000000000003';
select is(public.hosting_respond(current_setting('test.hosting_id')::uuid,'declined','[]'::jsonb,'60000000-0000-4000-8000-000000000043',1)->'myInvitation'->>'status','declined','invitee can decline');

set local request.jwt.claim.sub='60000000-0000-4000-8000-000000000001';
select is(jsonb_array_length(public.hosting_get(current_setting('test.hosting_id')::uuid)->'acceptedParticipants'),1,'host sees accepted participants only');
select ok(not ((public.hosting_get(current_setting('test.hosting_id')::uuid)->'acceptedParticipants') @> '[{"userId":"60000000-0000-4000-8000-000000000003"}]'::jsonb),'host projection does not expose declined invitee');
select is(public.hosting_cancel(current_setting('test.hosting_id')::uuid,'60000000-0000-4000-8000-000000000051',1)->>'status','cancelled','host can cancel with expected version');
select lives_ok($$delete from public.availability_slots$$,'availability can be deleted once hosting is cancelled');

select * from finish();
rollback;
