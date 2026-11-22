-- Row-level security: shops are isolated from each other, staff cannot edit
-- the profile, membership and invites are not directly writable.
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner-a@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'owner-b@example.com'),
  ('cccccccc-0000-0000-0000-000000000001', 'staff-a@example.com');

-- Owner A creates shop A and some data.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
do $$ begin perform create_shop('{"id":"shop-a","name":"Shop A","type":"grocery"}'); end $$;
insert into product (id, profile_id, name, stock_qty) values ('pa1', 'shop-a', 'Rice', 10);
insert into customer (id, profile_id, name) values ('ca1', 'shop-a', 'Asha');
insert into expense (id, profile_id, amount_minor, date) values ('ea1', 'shop-a', 500, '2026-11-22');
insert into supplier (id, profile_id, name) values ('sa1', 'shop-a', 'Wholesale A');

-- Owner B creates shop B.
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
do $$ begin perform create_shop('{"id":"shop-b","name":"Shop B","type":"shoes"}'); end $$;
insert into product (id, profile_id, name) values ('pb1', 'shop-b', 'Sneaker');

-- Staff joins shop A (membership row written as the service would).
reset role;
insert into shop_member (profile_id, user_id, role)
values ('shop-a', 'cccccccc-0000-0000-0000-000000000001', 'staff');

-- Owner B sees only shop B.
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
select results_eq('select id from business_profile', array['shop-b'], 'B sees only its own profile');
select results_eq('select id from product', array['pb1'], 'B sees only its own products');
select is_empty('select 1 from customer union all select 1 from expense union all select 1 from supplier',
  'B sees no customers, expenses or suppliers of shop A');
select results_eq('select profile_id from shop_member', array['shop-b'], 'B sees only its own shop members');

with u as (update product set name = 'hacked' where id = 'pa1' returning 1)
select is(count(*)::int, 0, 'B cannot update A''s product') from u;
with d as (delete from customer where id = 'ca1' returning 1)
select is(count(*)::int, 0, 'B cannot delete A''s customer') from d;
select throws_ok(
  $$insert into product (id, profile_id, name) values ('px', 'shop-a', 'Planted')$$,
  '42501', null, 'B cannot insert into shop A');
select throws_ok(
  $$update product set profile_id = 'shop-a' where id = 'pb1'$$,
  '42501', null, 'B cannot move its own row into shop A');
select throws_ok(
  $$select record_sale('{"id":"sx","profile_id":"shop-a"}', '[]')$$,
  '42501', null, 'B cannot record a sale in shop A');
select throws_ok(
  $$select adjust_stock('pa1', null, 100)$$,
  'P0002', null, 'B cannot adjust A''s stock');

-- Owner A still sees its own data untouched.
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
select results_eq('select id, name from product', $$values ('pa1', 'Rice')$$, 'A''s product is intact');
select results_eq('select count(*)::int from customer', array[1], 'A''s customer is intact');

-- Staff of shop A reads and writes shop data but not the profile.
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000000001"}';
select results_eq('select id from product', array['pa1'], 'staff sees shop A products');
select lives_ok(
  $$insert into product (id, profile_id, name) values ('pa2', 'shop-a', 'Dal')$$,
  'staff can add a product');
with u as (update business_profile set name = 'Staff Shop' where id = 'shop-a' returning 1)
select is(count(*)::int, 0, 'staff cannot update the profile directly') from u;
select throws_ok(
  $$select update_profile('{"id":"shop-a","name":"Staff Shop"}')$$,
  '42501', null, 'staff cannot call update_profile');
select results_eq('select name from business_profile', array['Shop A'], 'profile name unchanged');

-- Membership and invites are not directly writable.
select throws_ok(
  $$insert into shop_member (profile_id, user_id, role)
    values ('shop-a', 'cccccccc-0000-0000-0000-000000000001', 'owner')$$,
  '42501', null, 'staff cannot write shop_member');
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
select throws_ok(
  $$delete from shop_member where profile_id = 'shop-a'$$,
  '42501', null, 'owner cannot write shop_member directly');
select throws_ok(
  $$select * from shop_invite$$,
  '42501', null, 'shop_invite is not readable directly');

-- Anonymous callers get nothing.
set local role anon;
select throws_ok($$select * from product$$, '42501', null, 'anon cannot read product');
select throws_ok(
  $$select create_shop('{"id":"shop-anon","name":"Anon","type":"general"}')$$,
  '42501', null, 'anon cannot call create_shop');

select * from finish();
rollback;
