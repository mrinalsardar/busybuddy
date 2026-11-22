-- create_invite / join_shop: owner-only, single-use, 7-day codes.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@example.com'),
  ('cccccccc-0000-0000-0000-000000000001', 'staff1@example.com'),
  ('cccccccc-0000-0000-0000-000000000002', 'staff2@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
do $$ begin perform create_shop('{"id":"shop-a","name":"Shop A","type":"general"}'); end $$;
insert into product (id, profile_id, name) values ('p1', 'shop-a', 'Tea');

create temp table t_code as select create_invite('shop-a') as code;

select matches((select code from t_code), '^[A-HJ-NP-Z2-9]{10}$', 'code is 10 unambiguous characters');
reset role;
select ok(
  (select expires_at > to_db_time(now() + interval '6 days 23 hours')
      and expires_at <= to_db_time(now() + interval '7 days')
   from shop_invite where code = (select code from t_code)),
  'invite expires in 7 days');
set local role authenticated;
select isnt((select code from t_code), create_invite('shop-a'), 'each invite gets a new code');

-- Staff 1 joins (case and spaces are forgiven).
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000000001"}';
select is_empty($$select 1 from product$$, 'before joining, staff sees nothing');
select is(join_shop('  ' || lower((select code from t_code)) || ' '), 'shop-a', 'join_shop returns the shop id');
select results_eq($$select id from product$$, array['p1'], 'after joining, staff sees shop data');
select results_eq(
  $$select role from shop_member where user_id = 'cccccccc-0000-0000-0000-000000000001'$$,
  array['staff'], 'joiner is staff');
select is(join_shop((select code from t_code)), 'shop-a', 'joining again as a member is harmless');
select throws_ok($$select create_invite('shop-a')$$, '42501', null, 'staff cannot create invites');

-- The code is single-use.
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000000002"}';
select throws_ok(format('select join_shop(%L)', (select code from t_code)),
  '22023', 'Invite code is invalid or expired', 'a used code is refused');
select throws_ok($$select join_shop('NOSUCHCODE')$$, '22023', null, 'an unknown code is refused');
select is_empty($$select 1 from shop_member$$, 'refused joiner is not a member');

reset role;
select results_eq(
  format($$select used_by from shop_invite where code = %L$$, (select code from t_code)),
  array['cccccccc-0000-0000-0000-000000000001'::uuid], 'invite records who used it');

-- An expired code is refused.
insert into shop_invite (code, profile_id, expires_at)
values ('EXPIRED234', 'shop-a', to_db_time(now() - interval '1 second'));
set local role authenticated;
select throws_ok($$select join_shop('EXPIRED234')$$, '22023', null, 'an expired code is refused');

-- Owner's member list now has both.
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
select results_eq($$select role from shop_member order by role$$, array['owner', 'staff'],
  'owner sees owner and staff');

-- Unauthenticated callers cannot join.
set local request.jwt.claims = '{}';
select throws_ok($$select join_shop('EXPIRED234')$$, '42501', null, 'join needs a signed-in user');

select * from finish();
rollback;
