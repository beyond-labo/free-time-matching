begin;
select no_plan();

select has_function('public','automatic_scheduling_snapshot',array[]::text[],'snapshot RPC exists');
select has_function('public','automatic_scheduling_tick',array[]::text[],'service tick exists');
select has_function('public','automatic_scheduling_respond',array['uuid','text','boolean','uuid','integer'],'typed response RPC exists');
select ok(not has_function_privilege('authenticated','public.automatic_scheduling_tick()','execute'),'client cannot run service tick');
select ok(not has_function_privilege('authenticated','public.automatic_scheduling_delivery_claim()','execute'),'client cannot claim device tokens');
select ok(not has_function_privilege('anon','public.automatic_scheduling_snapshot()','execute'),'anonymous caller cannot read snapshot');
select table_privs_are('private','scheduling_proposals','authenticated',array[]::text[],'raw participant IDs and times are private');
select table_privs_are('private','scheduling_devices','authenticated',array[]::text[],'raw device tokens are private');
select table_privs_are('private','scheduling_reports','authenticated',array[]::text[],'reports are not exposed to participants');

insert into auth.users(id) values
 ('71000000-0000-4000-8000-000000000001'),('71000000-0000-4000-8000-000000000002'),
 ('71000000-0000-4000-8000-000000000003'),('71000000-0000-4000-8000-000000000004'),('71000000-0000-4000-8000-000000000005');
insert into public.user_profiles(user_id,nickname,preset_icon_key) values
 ('71000000-0000-4000-8000-000000000001','One','sun.max.fill'),
 ('71000000-0000-4000-8000-000000000002','Two','leaf.fill'),
 ('71000000-0000-4000-8000-000000000003','Three','figure.run'),
 ('71000000-0000-4000-8000-000000000004','Four','gamecontroller.fill'),
 ('71000000-0000-4000-8000-000000000005','Five','leaf.fill');
insert into public.friendships(user_low_id,user_high_id,last_operation_id) values
 ('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002',gen_random_uuid()),
 ('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000003',gen_random_uuid()),
 ('71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004',gen_random_uuid());
insert into public.availability_slots(id,owner_user_id,start_at,end_at)
select gen_random_uuid(),user_id,date_trunc('hour',now())+interval '2 hours',date_trunc('hour',now())+interval '50 hours'
from public.user_profiles where user_id in ('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002');
insert into public.availability_slots(id,owner_user_id,start_at,end_at)
select gen_random_uuid(),user_id,date_trunc('hour',now())+interval '3 hours',date_trunc('hour',now())+interval '3 hours 15 minutes'
from public.user_profiles where user_id in ('71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004','71000000-0000-4000-8000-000000000005');

set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select is(public.automatic_scheduling_snapshot()->>'enabled','false','existing account defaults off');
select is(public.automatic_scheduling_snapshot()->'permissions'->0->>'enabled','false','friend permission defaults off');
select is(jsonb_array_length(public.automatic_scheduling_snapshot()->'proposals'),0,'availability and friendship alone do not propose');
select lives_ok($$select public.automatic_scheduling_device(repeat('a',64),'sandbox',true)$$,'owner can register a device');
select lives_ok($$select public.automatic_scheduling_settings(true,'71000000-0000-4000-8000-000000000011')$$,'global enable is explicit');
select lives_ok($$select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000002',true,'71000000-0000-4000-8000-000000000012')$$,'one-sided friend permission saves');
select is(jsonb_array_length(public.automatic_scheduling_snapshot()->'proposals'),0,'one-sided permission does not propose');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000002';
select public.automatic_scheduling_settings(true,'71000000-0000-4000-8000-000000000013');
select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000001',true,'71000000-0000-4000-8000-000000000014');
select is(jsonb_array_length(public.automatic_scheduling_snapshot()->'proposals'),1,'bilateral permission creates one proposal');
select set_config('test.scheduling_id',public.automatic_scheduling_snapshot()->'proposals'->0->>'id',true);
select ok(not (public.automatic_scheduling_snapshot()->'proposals'->0 ? 'peer'),'proposal does not identify the friend');
select ok(not (public.automatic_scheduling_snapshot()->'proposals'->0 ? 'peerResponse'),'proposal omits peer response field');
select is(public.automatic_scheduling_snapshot()->'proposals'->0->>'myResponse','pending','availability is not participation');
reset role;
select is((select end_at-start_at from private.scheduling_proposals where id=current_setting('test.scheduling_id')::uuid),interval '24 hours','long common interval is capped at 24 hours');
select is((select start_at from private.scheduling_proposals where id=current_setting('test.scheduling_id')::uuid),date_trunc('hour',now())+interval '2 hours','earliest common start is selected');
select is((select count(*)::integer from private.scheduling_receipts),2,'each recipient gets one quota receipt');
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000002';
select public.automatic_scheduling_device(repeat('b',64),'production',true);
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000003';
select is(jsonb_array_length(public.automatic_scheduling_snapshot()->'proposals'),0,'third party does not see proposal existence');
select throws_ok($$select public.automatic_scheduling_respond(current_setting('test.scheduling_id')::uuid,'accepted',false,'71000000-0000-4000-8000-000000000019',1)$$,'P0002','scheduling_unavailable','third party cannot answer');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select public.automatic_scheduling_respond(current_setting('test.scheduling_id')::uuid,'accepted',true,'71000000-0000-4000-8000-000000000021',1);
select is(public.automatic_scheduling_snapshot()->'proposals'->0->>'status','pending','one acceptance does not confirm');
select is(public.automatic_scheduling_snapshot()->'proposals'->0->>'version','2','only own response version advances');
select lives_ok($$select public.automatic_scheduling_respond(current_setting('test.scheduling_id')::uuid,'accepted',true,'71000000-0000-4000-8000-000000000021',1)$$,'response replay keeps original version');
select throws_ok($$select public.automatic_scheduling_respond(current_setting('test.scheduling_id')::uuid,'accepted',false,'71000000-0000-4000-8000-000000000021',1)$$,'23505','scheduling_conflict','operation ID cannot change sharing choice');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000002';
select is(public.automatic_scheduling_snapshot()->'proposals'->0->'peer'->>'nickname','One','opted-in acceptance reveals own name');
select is(public.automatic_scheduling_snapshot()->'proposals'->0->>'peerResponse','accepted','opted-in acceptance is visible');
select is(public.automatic_scheduling_snapshot()->'proposals'->0->>'version','1','other acceptance does not stale own version');
select public.automatic_scheduling_respond(current_setting('test.scheduling_id')::uuid,'accepted',false,'71000000-0000-4000-8000-000000000022',1);
select is(public.automatic_scheduling_snapshot()->'proposals'->0->>'status','confirmed','both responses automatically confirm');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select is(public.automatic_scheduling_snapshot()->'proposals'->0->'peer'->>'nickname','Two','confirmed plan reveals peer despite private acceptance');
reset role;
select is((select count(*)::integer from private.scheduling_notifications where kind='confirmed'),2,'confirmation notifies both exactly once');
select is((select count(*)::integer from private.scheduling_deliveries),3,'late device registration skips past proposal and receives future confirmation');
select set_config('test.claim',public.automatic_scheduling_delivery_claim()::text,true);
select is(jsonb_array_length(current_setting('test.claim')::jsonb),3,'delivery claim leases a batch');
select is(jsonb_array_length(public.automatic_scheduling_delivery_claim()),0,'live lease prevents duplicate claims');
select public.automatic_scheduling_delivery_finish((current_setting('test.claim')::jsonb->0->>'id')::uuid,'retry');
select is(jsonb_array_length(public.automatic_scheduling_delivery_claim()),1,'transient delivery failure can retry');
select public.automatic_scheduling_delivery_finish((current_setting('test.claim')::jsonb->0->>'id')::uuid,'sent');
select is((select status from private.scheduling_deliveries where id=(current_setting('test.claim')::jsonb->0->>'id')::uuid),'sent','successful delivery persists');

set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select public.automatic_scheduling_settings(false,'71000000-0000-4000-8000-000000000031');
select is(public.automatic_scheduling_snapshot()->'proposals'->0->>'status','confirmed','disabling proposals does not cancel confirmed plan');
select public.automatic_scheduling_cancel(current_setting('test.scheduling_id')::uuid,'71000000-0000-4000-8000-000000000032',2);
select is(public.automatic_scheduling_snapshot()->'proposals'->0->>'status','cancelled','either participant can cancel');
select lives_ok($$select public.automatic_scheduling_cancel(current_setting('test.scheduling_id')::uuid,'71000000-0000-4000-8000-000000000032',2)$$,'cancel replay does not duplicate state');
select throws_ok($$select public.automatic_scheduling_feedback(current_setting('test.scheduling_id')::uuid,true,false,false,'71000000-0000-4000-8000-000000000033')$$,'23514','scheduling_invalid','future cancelled plan cannot count as played');
select public.automatic_scheduling_feedback(current_setting('test.scheduling_id')::uuid,false,true,true,'71000000-0000-4000-8000-000000000034');
select is(public.automatic_scheduling_snapshot()->'proposals'->0->'feedback'->>'bothersome','true','terminal proposal accepts optional annoyance feedback');
select public.automatic_scheduling_report(current_setting('test.scheduling_id')::uuid,'spam','71000000-0000-4000-8000-000000000035');
select public.automatic_scheduling_report_friend('71000000-0000-4000-8000-000000000003','other','71000000-0000-4000-8000-000000000036');
select public.automatic_scheduling_settings(true,'71000000-0000-4000-8000-000000000037');
select is(jsonb_array_length(public.automatic_scheduling_snapshot()->'proposals'),1,'cancel and re-enable do not reset weekly count');
reset role;
select is((select count(*)::integer from private.scheduling_notifications where kind='cancelled'),2,'cancel notification is unique per participant');
select is((select count(*)::integer from private.scheduling_reports),2,'proposal and friend reports persist independently');
update private.scheduling_receipts set created_at=now()-interval '8 days';
update private.scheduling_proposals set created_at=now()-interval '8 days';
select is(public.automatic_scheduling_tick(),0,'same pair is suppressed after seven days but before fourteen');
update private.scheduling_receipts set created_at=now()-interval '15 days';
update private.scheduling_proposals set created_at=now()-interval '15 days';
select is(public.automatic_scheduling_tick(),1,'pair becomes eligible after fourteen days');
select set_config('test.second_id',(select id::text from private.scheduling_proposals where status='pending'),true);
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select public.availability_union_interval(date_trunc('hour',now())+interval '2 hours',date_trunc('hour',now())+interval '50 hours',null,'privateUntilAccepted','71000000-0000-4000-8000-000000000041');
reset role;
select is((select status from private.scheduling_proposals where id=current_setting('test.second_id')::uuid),'pending','OR delete/reinsert does not transiently invalidate proposal');
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select public.availability_subtract_interval(date_trunc('hour',now())+interval '2 hours',date_trunc('hour',now())+interval '2 hours 15 minutes','71000000-0000-4000-8000-000000000042');
reset role;
select is((select status from private.scheduling_proposals where id=current_setting('test.second_id')::uuid),'cancelled','removing proposal time cancels only pending proposal');
select is(public.automatic_scheduling_tick(),0,'time edit does not immediately re-propose');

-- Separate pair verifies the minimum interval and relationship lifecycle.
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000003';
select public.automatic_scheduling_settings(true,'71000000-0000-4000-8000-000000000051');
select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000004',true,'71000000-0000-4000-8000-000000000052');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000004';
select public.automatic_scheduling_settings(true,'71000000-0000-4000-8000-000000000053');
select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000003',true,'71000000-0000-4000-8000-000000000054');
select set_config('test.minimum_id',public.automatic_scheduling_snapshot()->'proposals'->0->>'id',true);
reset role;
select is((select end_at-start_at from private.scheduling_proposals where id=current_setting('test.minimum_id')::uuid),interval '15 minutes','minimum fifteen-minute overlap is eligible');
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000003';
select public.remove_friendship('71000000-0000-4000-8000-000000000004','71000000-0000-4000-8000-000000000055',1);
reset role;
select is((select status from private.scheduling_proposals where id=current_setting('test.minimum_id')::uuid),'cancelled','friend removal cancels pending proposal');
select is((select count(*)::integer from private.scheduling_permissions where user_id in ('71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004') and enabled),0,'friend removal invalidates both directional permissions');
update public.friendships set active=true where user_low_id='71000000-0000-4000-8000-000000000003' and user_high_id='71000000-0000-4000-8000-000000000004';
select is((select count(*)::integer from private.scheduling_permissions where user_id in ('71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004') and enabled),0,'friend re-add does not restore consent');
update private.scheduling_receipts set created_at=now()-interval '15 days' where user_id in ('71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004');
update private.scheduling_proposals set created_at=now()-interval '15 days' where id=current_setting('test.minimum_id')::uuid;
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000003';
select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000004',true,'71000000-0000-4000-8000-000000000061');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000004';
select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000003',true,'71000000-0000-4000-8000-000000000062');
reset role;
select set_config('test.retire_id',(select id::text from private.scheduling_proposals where status='pending'),true);
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000003';
select public.automatic_scheduling_respond(current_setting('test.retire_id')::uuid,'accepted',false,'71000000-0000-4000-8000-000000000063',1);
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000004';
select ok(not (public.automatic_scheduling_snapshot()->'proposals'->0 ? 'peer'),'private acceptance remains anonymous before both OK');
select public.automatic_scheduling_respond(current_setting('test.retire_id')::uuid,'accepted',false,'71000000-0000-4000-8000-000000000064',1);
reset role;
-- A past plan remains a factual confirmed event when the peer retires. Its
-- identity fields must disappear without making the entire snapshot invalid.
insert into private.scheduling_proposals(id,user_low_id,user_high_id,start_at,end_at,status,created_at,confirmed_at)
values('71000000-0000-4000-8000-000000000091','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004',
 date_trunc('hour',now())-interval '14 days',date_trunc('hour',now())-interval '14 days'+interval '1 hour','confirmed',now()-interval '15 days',now()-interval '15 days');
insert into private.scheduling_responses(proposal_id,user_id,response,version) values
 ('71000000-0000-4000-8000-000000000091','71000000-0000-4000-8000-000000000003','accepted',2),
 ('71000000-0000-4000-8000-000000000091','71000000-0000-4000-8000-000000000004','accepted',2);
insert into public.account_deletion_requests(user_id,idempotency_key,reference,status_token_hash)
values('71000000-0000-4000-8000-000000000004','scheduling-test-delete','scheduling-retire',repeat('f',64));
select is((select status from private.scheduling_proposals where id=current_setting('test.retire_id')::uuid),'cancelled','retirement cancels future confirmed plan');
select is((select count(*)::integer from private.scheduling_notifications where user_id='71000000-0000-4000-8000-000000000003' and proposal_id=current_setting('test.retire_id')::uuid and kind='cancelled'),1,'retirement notifies surviving participant');
delete from auth.users where id='71000000-0000-4000-8000-000000000004';
select is((select count(*)::integer from private.scheduling_receipts where user_id='71000000-0000-4000-8000-000000000003' and created_at>now()-interval '7 days'),1,'peer hard deletion does not erase recipient weekly receipt');
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000003';
select is((select value->>'status' from jsonb_array_elements(public.automatic_scheduling_snapshot()->'proposals') where value->>'id'='71000000-0000-4000-8000-000000000091'),'confirmed','past confirmed fact survives peer deletion');
select ok((select not (value ? 'peer') and not (value ? 'peerResponse') from jsonb_array_elements(public.automatic_scheduling_snapshot()->'proposals') where value->>'id'='71000000-0000-4000-8000-000000000091'),'deleted peer is omitted rather than returned as null profile');
select lives_ok($$select public.automatic_scheduling_feedback('71000000-0000-4000-8000-000000000091',true,false,false,'71000000-0000-4000-8000-000000000067')$$,'past played feedback remains possible after peer deletion');
reset role;
insert into public.friendships(user_low_id,user_high_id,last_operation_id) values('71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000005',gen_random_uuid());
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000003';
select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000005',true,'71000000-0000-4000-8000-000000000071');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000005';
select public.automatic_scheduling_settings(true,'71000000-0000-4000-8000-000000000072');
select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000003',true,'71000000-0000-4000-8000-000000000073');
select is(jsonb_array_length(public.automatic_scheduling_snapshot()->'proposals'),0,'surviving recipient quota blocks another friend after peer deletion');

-- Anonymous proposal block resolves peer server-side and affects old API guards.
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select public.automatic_scheduling_block_proposal(current_setting('test.second_id')::uuid,'71000000-0000-4000-8000-000000000081');
reset role;
select ok(private.scheduling_blocked('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002'),'anonymous block persists without client knowing peer ID');
select throws_ok($$insert into public.friendships(user_low_id,user_high_id,last_operation_id) values('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002',gen_random_uuid()) on conflict(user_low_id,user_high_id) do update set active=true$$,'P0001','friendship_unavailable','blocked friendship cannot be resurrected');
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select throws_ok($$select public.automatic_scheduling_permission('71000000-0000-4000-8000-000000000002',true,'71000000-0000-4000-8000-000000000082')$$,'P0002','scheduling_unavailable','blocked friend cannot receive permission');
reset role;

select ok((select bool_and(payload ? 'sha256' and (payload->>'sha256') ~ '^[0-9a-f]{64}$' and not (payload ? 'friendId'))
  from private.scheduling_operations),'replay ledger retains input digest rather than peer identity');
-- Safety reports do not require matching eligibility or a proposal. Both
-- request participants and former friends can still report a known subject.
insert into public.friendship_requests(requester_id,addressee_id,last_operation_id) values
 ('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000101');
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000005';
select lives_ok($$select public.automatic_scheduling_report_friend('71000000-0000-4000-8000-000000000001','spam','71000000-0000-4000-8000-000000000102')$$,'friend request receiver can report sender without friendship or proposal');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select lives_ok($$select public.automatic_scheduling_report_friend('71000000-0000-4000-8000-000000000005','other','71000000-0000-4000-8000-000000000103')$$,'friend request sender can report recipient without friendship or proposal');
select lives_ok($$select public.automatic_scheduling_report_friend('71000000-0000-4000-8000-000000000005','other','71000000-0000-4000-8000-000000000103')$$,'request subject report replays without another report');
reset role;
update public.friendships set active=false,version=version+1
 where user_low_id='71000000-0000-4000-8000-000000000001' and user_high_id='71000000-0000-4000-8000-000000000003';
set local role authenticated;
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000001';
select lives_ok($$select public.automatic_scheduling_report_friend('71000000-0000-4000-8000-000000000003','harassment','71000000-0000-4000-8000-000000000104')$$,'former friend remains reportable without a proposal');
set local request.jwt.claim.sub='71000000-0000-4000-8000-000000000002';
select throws_ok($$select public.automatic_scheduling_report_friend('71000000-0000-4000-8000-000000000005','spam','71000000-0000-4000-8000-000000000105')$$,'P0002','scheduling_unavailable','unrelated caller cannot report arbitrary profile IDs');
reset role;
select is((select count(*)::integer from private.scheduling_reports),5,'request and former-friend reports persist once each');
select is((select count(*)::integer from private.scheduling_reports
 where reporter_id='71000000-0000-4000-8000-000000000001'
   and ((operation_id='71000000-0000-4000-8000-000000000035' and proposal_id=current_setting('test.scheduling_id')::uuid)
     or (operation_id='71000000-0000-4000-8000-000000000103' and proposal_id is null and target_user_id='71000000-0000-4000-8000-000000000005'))),
 2,'proposal and friend receipt operation IDs persist once each, including replay');
select * from finish();
rollback;
