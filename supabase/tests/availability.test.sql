begin;

select plan(15);

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

select is((select count(*)::integer from public.availability_slots), 1, 'owner sees own slot');
select is((select visibility from public.availability_slots limit 1), 'privateUntilAccepted', 'default visibility is private');
select throws_ok(
  $$insert into public.availability_slots (id, owner_user_id, start_at, end_at)
    values ('30000000-0000-4000-8000-000000000012',
      '30000000-0000-4000-8000-000000000001',
      date_trunc('hour', now()) + interval '2 hours 15 minutes',
      date_trunc('hour', now()) + interval '3 hours 15 minutes')$$,
  '23P01',
  null,
  'overlapping own slots are rejected by the database'
);

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
