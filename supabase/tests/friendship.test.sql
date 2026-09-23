begin;

select plan(38);

select has_table('public', 'friend_invite_codes', 'invite codes exist');
select has_table('public', 'friendship_requests', 'friendship requests exist');
select has_table('public', 'friendships', 'friendships exist');
select has_table('public', 'friendship_operations', 'operation ledger exists');

select policies_are('public', 'friend_invite_codes', array[]::text[], 'invite codes have no direct policies');
select policies_are('public', 'friendship_requests', array[]::text[], 'requests have no direct policies');
select policies_are('public', 'friendships', array[]::text[], 'friendships have no direct policies');
select policies_are('public', 'friendship_operations', array[]::text[], 'operations have no direct policies');

select table_privs_are('public', 'friend_invite_codes', 'authenticated', array[]::text[], 'codes are RPC-only');
select table_privs_are('public', 'friendship_requests', 'authenticated', array[]::text[], 'requests are RPC-only');
select table_privs_are('public', 'friendships', 'authenticated', array[]::text[], 'friendships are RPC-only');
select table_privs_are('public', 'friendship_operations', 'authenticated', array[]::text[], 'operations are RPC-only');

select has_function('public', 'friendship_snapshot', array[]::text[], 'snapshot RPC exists');
select has_function('public', 'rotate_friend_invite_code', array['text', 'text', 'timestamp with time zone'], 'rotate RPC exists');
select has_function('public', 'ensure_friend_invite_code', array['text', 'text', 'timestamp with time zone'], 'ensure RPC exists');
select has_function('public', 'resolve_friend_invite_code', array['text'], 'resolve RPC exists');
select has_function('public', 'send_friend_request', array['text', 'uuid'], 'send RPC exists');
select has_function('public', 'transition_friend_request', array['uuid', 'text', 'uuid', 'integer'], 'transition RPC exists');
select has_function('public', 'remove_friendship', array['uuid', 'uuid', 'integer'], 'remove RPC exists');

insert into auth.users (id)
values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002'),
  ('10000000-0000-4000-8000-000000000003');

insert into public.user_profiles (user_id, nickname, preset_icon_key)
values
  ('10000000-0000-4000-8000-000000000001', 'Himari', 'sun.max.fill'),
  ('10000000-0000-4000-8000-000000000002', 'Riku', 'figure.run'),
  ('10000000-0000-4000-8000-000000000003', 'Sora', 'leaf.fill');

insert into public.friend_invite_codes (owner_user_id, code, code_hash, expires_at)
values (
  '10000000-0000-4000-8000-000000000003',
  'HIMA-ZZZZ-ZZZZ-ZZZZ-ZZZZ',
  repeat('b', 64),
  now() + interval '7 days'
);

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select is(public.friendship_snapshot()->'invite_code', 'null'::jsonb, 'snapshot starts without a code');
select is(
  public.rotate_friend_invite_code(
    'HIMA-ABCD-EFGH-JKMP-QRST',
    repeat('a', 64),
    now() + interval '7 days'
  )->'invite_code'->>'value',
  'HIMA-ABCD-EFGH-JKMP-QRST',
  'owner receives rotated code'
);
select throws_ok(
  $$select public.resolve_friend_invite_code(repeat('a', 64))$$,
  'P0001',
  'invite_code_unavailable',
  'self-owned code is indistinguishable from unavailable code'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
select is(
  public.ensure_friend_invite_code(
    'HIMA-CDEF-GHJK-MPQR-STUV',
    repeat('c', 64),
    now() + interval '7 days'
  )->'invite_code'->>'value',
  'HIMA-CDEF-GHJK-MPQR-STUV',
  'initial ensure issues a code for an existing profile'
);
select is(
  public.resolve_friend_invite_code(repeat('a', 64))->>'nickname',
  'Himari',
  'other user resolves the minimum profile'
);
select is(
  jsonb_array_length(public.send_friend_request(
    repeat('a', 64),
    '20000000-0000-4000-8000-000000000001'
  )->'outgoing_requests'),
  1,
  'sender receives one outgoing request'
);
select throws_ok(
  $$select public.send_friend_request(
      repeat('b', 64),
      '20000000-0000-4000-8000-000000000001'
    )$$,
  'P0001',
  'friendship_conflict',
  'an operation ID cannot be reused for a different target'
);

reset role;
do $$
begin
  perform set_config(
    'test.friendship_request_id',
    (select id::text from public.friendship_requests where status = 'pending'),
    true
  );
end
$$;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set local role authenticated;
select is(jsonb_array_length(public.friendship_snapshot()->'incoming_requests'), 1, 'recipient sees incoming request');

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select public.transition_friend_request(
      current_setting('test.friendship_request_id')::uuid,
      'accept',
      '20000000-0000-4000-8000-000000000004',
      999
    )$$,
  'P0001',
  'friendship_unavailable',
  'a non-party cannot distinguish request state or version'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
select is(
  jsonb_array_length(public.transition_friend_request(
    current_setting('test.friendship_request_id')::uuid,
    'accept',
    '20000000-0000-4000-8000-000000000002',
    1
  )->'friends'),
  1,
  'accept atomically creates one friendship'
);
select throws_ok(
  $$select public.transition_friend_request(
      current_setting('test.friendship_request_id')::uuid,
      'accept',
      '20000000-0000-4000-8000-000000000003',
      1
    )$$,
  'P0001',
  'friendship_conflict',
  'stale transition reports a conflict'
);

select is(
  jsonb_array_length(public.remove_friendship(
    '10000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000005',
    1
  )->'friends'),
  0,
  'remove hides the inactive friendship'
);
select is(
  jsonb_array_length(public.remove_friendship(
    '10000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000005',
    1
  )->'friends'),
  0,
  'remove replay is idempotent'
);
select is(
  jsonb_array_length(public.send_friend_request(
    repeat('c', 64),
    '20000000-0000-4000-8000-000000000006'
  )->'outgoing_requests'),
  1,
  'a removed pair can request friendship again'
);

reset role;
do $$
begin
  perform set_config(
    'test.friendship_request_id',
    (select id::text from public.friendship_requests where status = 'pending'),
    true
  );
end
$$;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(
  (public.transition_friend_request(
    current_setting('test.friendship_request_id')::uuid,
    'accept',
    '20000000-0000-4000-8000-000000000007',
    1
  )->'friends'->0->>'version')::integer,
  3,
  're-established friendship advances the relation version monotonically'
);

select is(
  jsonb_array_length(public.send_friend_request(
    repeat('b', 64),
    '20000000-0000-4000-8000-000000000008'
  )->'outgoing_requests'),
  1,
  'a second pair can create a pending request'
);
reset role;
do $$
begin
  perform set_config(
    'test.friendship_request_id',
    (select id::text from public.friendship_requests where status = 'pending'),
    true
  );
end
$$;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
set local role authenticated;
select is(
  jsonb_array_length(public.transition_friend_request(
    current_setting('test.friendship_request_id')::uuid,
    'reject',
    '20000000-0000-4000-8000-000000000009',
    1
  )->'incoming_requests'),
  0,
  'recipient can reject a pending request'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
select lives_ok(
  $$select public.send_friend_request(
      repeat('b', 64),
      '20000000-0000-4000-8000-000000000010'
    )$$,
  'sender can create another request after a rejection'
);
reset role;
do $$
begin
  perform set_config(
    'test.friendship_request_id',
    (select id::text from public.friendship_requests where status = 'pending'),
    true
  );
end
$$;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(
  jsonb_array_length(public.transition_friend_request(
    current_setting('test.friendship_request_id')::uuid,
    'cancel',
    '20000000-0000-4000-8000-000000000011',
    1
  )->'outgoing_requests'),
  0,
  'sender can cancel a pending request'
);

select * from finish();
rollback;
