begin;

select plan(29);

select has_table('public', 'availability_slots', 'availability table exists');
select col_is_pk('public', 'availability_slots', 'id', 'slot id is primary key');
select col_is_fk('public', 'availability_slots', 'owner_user_id', 'slot owner references auth user');
select col_has_default('public', 'availability_slots', 'visibility', 'visibility has private default');
select has_index('public', 'availability_slots', 'availability_slots_no_overlap', 'overlap index exists');
select policies_are('public', 'availability_slots', ARRAY[
  'availability_slots_select_own',
  'availability_slots_insert_own',
  'availability_slots_update_own',
  'availability_slots_delete_own'
]);
select col_type_is('public', 'availability_slots', 'start_at', 'timestamp with time zone', 'start is an instant');
select col_type_is('public', 'availability_slots', 'end_at', 'timestamp with time zone', 'end is an instant');
select has_function('public', 'availability_union_interval', ARRAY['timestamp with time zone', 'timestamp with time zone', 'text', 'text', 'uuid'], 'union RPC exists');
select has_function('public', 'availability_subtract_interval', ARRAY['timestamp with time zone', 'timestamp with time zone', 'uuid'], 'subtract RPC exists');

insert into auth.users (id)
values
  ('30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000002');

set local role authenticated;
set local request.jwt.claim.sub = '30000000-0000-4000-8000-000000000001';

insert into public.availability_slots (id, owner_user_id, start_at, end_at)
values (
  '30000000-0000-4000-8000-000000000011',
  '30000000-0000-4000-8000-000000000001',
  date_trunc('hour', now()) + interval '2 hours',
  date_trunc('hour', now()) + interval '3 hours'
);

insert into public.availability_slots (id, owner_user_id, start_at, end_at)
values
  ('30000000-0000-4000-8000-000000000015', '30000000-0000-4000-8000-000000000001', date_trunc('hour', now()) + interval '3 hours 15 minutes', date_trunc('hour', now()) + interval '3 hours 30 minutes'),
  ('30000000-0000-4000-8000-000000000016', '30000000-0000-4000-8000-000000000001', date_trunc('hour', now()) + interval '3 hours 30 minutes', date_trunc('hour', now()) + interval '3 hours 45 minutes');

select is((select count(*)::integer from public.availability_slots), 3, 'owner sees own slots');
select is((select visibility from public.availability_slots limit 1), 'privateUntilAccepted', 'default visibility is private');
select is(
  jsonb_array_length(public.availability_union_interval(
    date_trunc('hour', now()) + interval '3 hours',
    date_trunc('hour', now()) + interval '3 hours 15 minutes',
    'meal', 'shareOnHosting', '30000000-0000-4000-8000-000000000021'
  )),
  1,
  'union merges touching intervals through a multi-slot chain'
);
select is(
  (select category from public.availability_slots where start_at = date_trunc('hour', now()) + interval '2 hours'),
  'meal'::text,
  'union applies request category to the merged interval'
);
select throws_ok(
  $$select public.availability_union_interval(
    date_trunc('hour', now()) + interval '3 hours',
    date_trunc('hour', now()) + interval '3 hours 15 minutes',
    'game', 'shareOnHosting', '30000000-0000-4000-8000-000000000021')$$,
  '23505', 'availability_operation_conflict',
  'an operation id cannot be replayed with different metadata'
);
select throws_ok(
  $$select public.availability_union_interval(
    date_trunc('hour', now()) + interval '5 hours 0.5 seconds',
    date_trunc('hour', now()) + interval '5 hours 15 minutes',
    null, 'privateUntilAccepted', '30000000-0000-4000-8000-000000000024')$$,
  '23514', 'availability_invalid',
  'fractional-second start is not a 15-minute boundary'
);
select is(
  jsonb_array_length(public.availability_subtract_interval(
    date_trunc('hour', now()) + interval '2 hours 15 minutes',
    date_trunc('hour', now()) + interval '3 hours 15 minutes',
    '30000000-0000-4000-8000-000000000022'
  )),
  2,
  'subtract splits a slot into its left and right remnants'
);
select is(
  jsonb_array_length(public.availability_subtract_interval(
    date_trunc('hour', now()) + interval '2 hours 15 minutes',
    date_trunc('hour', now()) + interval '3 hours 15 minutes',
    '30000000-0000-4000-8000-000000000022'
  )),
  2,
  'replayed subtract operation returns its saved result'
);
insert into public.availability_slots(id, owner_user_id, start_at, end_at, category, visibility)
values ('30000000-0000-4000-8000-000000000017', '30000000-0000-4000-8000-000000000001',
  date_trunc('hour', now()) + interval '4 hours', date_trunc('hour', now()) + interval '5 hours',
  'game', 'privateUntilAccepted');
select is(
  jsonb_array_length(public.availability_subtract_interval(
    date_trunc('hour', now()) + interval '3 hours 30 minutes',
    date_trunc('hour', now()) + interval '4 hours 30 minutes',
    '30000000-0000-4000-8000-000000000023'
  )),
  3,
  'one subtraction cuts multiple slots and retains both outer remnants'
);
select is(
  (select category from public.availability_slots where start_at = date_trunc('hour', now()) + interval '4 hours 30 minutes'),
  'game'::text,
  'right remnant retains its original category'
);
select is(
  (select visibility from public.availability_slots where start_at = date_trunc('hour', now()) + interval '3 hours 15 minutes'),
  'shareOnHosting'::text,
  'left remnant retains its original visibility'
);
select throws_ok(
  $$insert into public.availability_slots (id, owner_user_id, start_at, end_at)
    values ('30000000-0000-4000-8000-000000000012',
      '30000000-0000-4000-8000-000000000001',
      date_trunc('hour', now()) + interval '2 hours',
      date_trunc('hour', now()) + interval '2 hours 15 minutes')$$,
  '23P01',
  null,
  'overlapping own slots are rejected by the database'
);

-- now() is fixed within this rollback transaction. Move only saved operation
-- payloads outside the current window to model records persisted before expiry.
-- Preserve result JSON exactly; past availability writes would violate triggers.
reset role;
update private.availability_interval_operations set payload=payload || jsonb_build_object(
 'start_at',date_trunc('hour',now())-interval '2 hours',
 'end_at',date_trunc('hour',now())-interval '1 hour')
 where owner_user_id='30000000-0000-4000-8000-000000000001'
 and operation_id in ('30000000-0000-4000-8000-000000000021','30000000-0000-4000-8000-000000000022');
select set_config('test.union_saved_result',(select result::text from private.availability_interval_operations
 where owner_user_id='30000000-0000-4000-8000-000000000001' and operation_id='30000000-0000-4000-8000-000000000021'),true);
select set_config('test.subtract_saved_result',(select result::text from private.availability_interval_operations
 where owner_user_id='30000000-0000-4000-8000-000000000001' and operation_id='30000000-0000-4000-8000-000000000022'),true);
set local role authenticated;
select is(public.availability_union_interval(date_trunc('hour',now())-interval '2 hours',
 date_trunc('hour',now())-interval '1 hour','meal','shareOnHosting','30000000-0000-4000-8000-000000000021'),
 current_setting('test.union_saved_result')::jsonb,'out-of-window union replay returns exact saved result after later interval mutations');
select is(public.availability_subtract_interval(date_trunc('hour',now())-interval '2 hours',
 date_trunc('hour',now())-interval '1 hour','30000000-0000-4000-8000-000000000022'),
 current_setting('test.subtract_saved_result')::jsonb,'out-of-window subtract replay returns exact saved result after later interval mutations');
select throws_ok($$select public.availability_subtract_interval(date_trunc('hour',now())-interval '3 hours',
 date_trunc('hour',now())-interval '1 hour','30000000-0000-4000-8000-000000000022')$$,
 '23505','availability_operation_conflict','out-of-window subtract replay rejects changed interval');

set local request.jwt.claim.sub = '30000000-0000-4000-8000-000000000002';
select is((select count(*)::integer from public.availability_slots), 0, 'other user cannot read a private slot');
select throws_ok(
  $$insert into public.availability_slots (id, owner_user_id, start_at, end_at)
    values ('30000000-0000-4000-8000-000000000013',
      '30000000-0000-4000-8000-000000000001',
      date_trunc('hour', now()) + interval '4 hours',
      date_trunc('hour', now()) + interval '5 hours')$$,
  '42501',
  null,
  'other user cannot create a slot for the owner'
);

reset role;
insert into public.account_deletion_requests (
  user_id, idempotency_key, reference, status_token_hash
) values (
  '30000000-0000-4000-8000-000000000001',
  'delete-availability-owner',
  'deletion-availability-owner',
  repeat('c', 64)
);

set local role authenticated;
set local request.jwt.claim.sub = '30000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from public.availability_slots), 0, 'deletion request blocks own slot reads');
select throws_ok(
  $$insert into public.availability_slots (id, owner_user_id, start_at, end_at)
    values ('30000000-0000-4000-8000-000000000014',
      '30000000-0000-4000-8000-000000000001',
      date_trunc('hour', now()) + interval '4 hours',
      date_trunc('hour', now()) + interval '5 hours')$$,
  '42501',
  null,
  'deletion request blocks slot creation'
);

select * from finish();
rollback;
