begin;

select plan(23);

select has_table('public', 'user_profiles', 'user_profiles exists');
select has_table('public', 'account_deletion_requests', 'deletion requests exist');
select col_is_pk('public', 'user_profiles', 'user_id', 'profile identity is the primary key');
select has_column('public', 'user_profiles', 'nickname', 'profile has nickname');
select has_column('public', 'user_profiles', 'preset_icon_key', 'profile has preset icon');
select policies_are(
  'public',
  'user_profiles',
  array[
    'user_profiles_insert_own_active',
    'user_profiles_select_own_active',
    'user_profiles_update_own_active'
  ],
  'profile policies do not grant delete access'
);
select policies_are(
  'public',
  'account_deletion_requests',
  array[]::text[],
  'deletion rows are not directly exposed through RLS'
);
select table_privs_are(
  'public',
  'user_profiles',
  'authenticated',
  array['INSERT', 'SELECT', 'UPDATE'],
  'authenticated profile grants are least privilege'
);
select table_privs_are(
  'public',
  'user_profiles',
  'anon',
  array[]::text[],
  'anonymous users have no profile grants'
);
select table_privs_are(
  'public',
  'account_deletion_requests',
  'authenticated',
  array[]::text[],
  'authenticated users cannot read hashes or mutate deletion state'
);
select table_privs_are(
  'public',
  'account_deletion_requests',
  'anon',
  array[]::text[],
  'anonymous users cannot read status token hashes'
);
select has_function(
  'public',
  'is_account_active',
  array[]::text[],
  'authenticated access gate exposes only a boolean'
);
select function_privs_are(
  'private',
  'account_is_active',
  array['uuid'],
  'authenticated',
  array[]::text[],
  'authenticated cannot probe another user deletion state'
);
select has_function(
  'public',
  'get_account_deletion_status',
  array['text', 'text'],
  'opaque status lookup exists'
);
select col_is_null(
  'public',
  'account_deletion_requests',
  'completed_at',
  'completion timestamp is nullable until completion'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_profiles'::regclass),
  'profile row level security is enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.account_deletion_requests'::regclass),
  'deletion request row level security is enabled'
);

insert into auth.users (id)
values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000003'),
  ('00000000-0000-0000-0000-000000000004');

insert into public.user_profiles (user_id, nickname, preset_icon_key)
values
  ('00000000-0000-0000-0000-000000000001', 'Own profile', 'sun.max.fill'),
  ('00000000-0000-0000-0000-000000000002', 'Other profile', 'leaf.fill');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select results_eq(
  $$select nickname from public.user_profiles order by nickname$$,
  $$values ('Own profile'::text)$$,
  'authenticated user can read only their own profile'
);

select throws_ok(
  $$insert into public.user_profiles (user_id, nickname, preset_icon_key)
    values ('00000000-0000-0000-0000-000000000003', 'Cross-user insert', 'sun.max.fill')$$,
  '42501',
  null,
  'authenticated user cannot insert another user profile'
);

select results_eq(
  $$with changed as (
      update public.user_profiles
      set nickname = 'Cross-user update'
      where user_id = '00000000-0000-0000-0000-000000000002'
      returning 1
    )
    select count(*)::bigint from changed$$,
  $$values (0::bigint)$$,
  'authenticated user cannot update another user profile'
);

reset role;

select throws_ok(
  $$insert into public.user_profiles (user_id, nickname, preset_icon_key)
    values ('00000000-0000-0000-0000-000000000003', '', 'sun.max.fill')$$,
  '23514',
  null,
  'database rejects an empty nickname'
);

select throws_ok(
  $$insert into public.user_profiles (user_id, nickname, preset_icon_key)
    values ('00000000-0000-0000-0000-000000000004', 'Invalid icon', 'person.crop.circle')$$,
  '23514',
  null,
  'database rejects an icon outside the preset allowlist'
);

insert into public.account_deletion_requests (
  user_id,
  idempotency_key,
  reference,
  status_token_hash
)
values (
  '00000000-0000-0000-0000-000000000001',
  'delete-operation-1',
  'deletion-reference-1',
  repeat('a', 64)
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select results_eq(
  $$select count(*)::bigint from public.user_profiles$$,
  $$values (0::bigint)$$,
  'deletion request immediately blocks profile reads'
);

reset role;

select * from finish();
rollback;
