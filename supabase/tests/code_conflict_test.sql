-- Duplicate SKU/barcode: accepted (never blocks an upload) and flagged in
-- code_conflict; archiving or editing a product resolves its conflicts.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner-a@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'owner-b@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
do $$ begin perform create_shop('{"id":"shop-b","name":"Shop B","type":"general"}'); end $$;

set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
do $$ begin perform create_shop('{"id":"shop-a","name":"Shop A","type":"general"}'); end $$;
insert into product (id, profile_id, name, sku, barcode) values ('p1', 'shop-a', 'Shirt', 'S1', 'B1');

-- Two devices created products with the same codes while offline.
select lives_ok(
  $$insert into product (id, profile_id, name, sku) values ('p2', 'shop-a', 'Shirt (tablet)', 'S1')$$,
  'duplicate active SKU is accepted');
select lives_ok(
  $$insert into product (id, profile_id, name, barcode) values ('p3', 'shop-a', 'Shirt (phone)', 'B1')$$,
  'duplicate active barcode is accepted');
select results_eq(
  $$select product_id, other_product_id, field, value, resolved_at from code_conflict order by field$$,
  $$values ('p3'::text, 'p1'::text, 'barcode'::text, 'B1'::text, null::text),
           ('p2', 'p1', 'sku', 'S1', null)$$,
  'each duplicate is flagged once');
select matches((select created_at from code_conflict where product_id = 'p2'),
  '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$', 'conflict created_at uses db_time format');

-- Products without codes, archived products and re-saves do not add conflicts.
insert into product (id, profile_id, name) values ('p4', 'shop-a', 'Loose'), ('p5', 'shop-a', 'Loose 2');
insert into product (id, profile_id, name, sku, archived) values ('p6', 'shop-a', 'Old shirt', 'S1', 1);
update product set sku = 'S1', name = 'Shirt (tablet) v2' where id = 'p2';
select is((select count(*)::int from code_conflict), 2,
  'no conflict for null codes, archived products or an unchanged re-save');

-- Archiving p1 resolves both of its conflicts.
update product set archived = 1 where id = 'p1';
select is((select count(*)::int from code_conflict where resolved_at is null), 0,
  'archiving a product resolves its conflicts');
select matches((select min(resolved_at) from code_conflict),
  '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$', 'resolved_at uses db_time format');

-- Restoring it flags them again.
update product set archived = 0 where id = 'p1';
select results_eq(
  $$select product_id, other_product_id, field from code_conflict where resolved_at is null order by field$$,
  $$values ('p1'::text, 'p3'::text, 'barcode'::text), ('p1', 'p2', 'sku')$$,
  'un-archiving flags the duplicates again');

-- Editing a code resolves only that code's conflict.
update product set sku = 'S2' where id = 'p2';
select results_eq(
  $$select field from code_conflict where resolved_at is null$$, array['barcode'],
  'changing the SKU resolves the SKU conflict only');
update product set barcode = 'B9' where id = 'p1';
select is((select count(*)::int from code_conflict where resolved_at is null), 0,
  'changing the other product''s barcode resolves the barcode conflict');

-- Three products with one code: archiving one leaves the other pair open.
insert into product (id, profile_id, name, sku) values ('p7', 'shop-a', 'Shirt 7', 'S2');
insert into product (id, profile_id, name, sku) values ('p8', 'shop-a', 'Shirt 8', 'S2');
select is((select count(*)::int from code_conflict where resolved_at is null and value = 'S2'), 3,
  'a third duplicate is flagged against both others');
update product set archived = 1 where id = 'p2';
select results_eq(
  $$select product_id, other_product_id from code_conflict where resolved_at is null and value = 'S2'$$,
  $$values ('p8'::text, 'p7'::text)$$,
  'archiving one of three leaves the remaining pair flagged');

-- The same code in another shop is no conflict, and shops cannot see each
-- other's conflicts.
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
insert into product (id, profile_id, name, sku) values ('pb1', 'shop-b', 'Shirt', 'S2');
select is_empty($$select 1 from code_conflict$$, 'shop B sees no conflicts');
reset role;
select is((select count(*)::int from code_conflict where profile_id = 'shop-b'), 0,
  'the same SKU in another shop is no conflict');
set local role authenticated;

-- One statement inserting two products with the same new SKU flags the pair
-- once.
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
insert into product (id, profile_id, name, sku) values ('p9', 'shop-a', 'A', 'NEW'), ('p10', 'shop-a', 'B', 'NEW');
select is((select count(*)::int from code_conflict where value = 'NEW'), 1,
  'a multi-row insert of one code is flagged once');

-- Members can mark a conflict resolved themselves.
with u as (update code_conflict set resolved_at = to_db_time(now()) where value = 'NEW' returning 1)
select is(count(*)::int, 1, 'a member can resolve a conflict') from u;

-- Deleting a product removes its conflict rows.
delete from product where id = 'p8';
select is((select count(*)::int from code_conflict where 'p8' in (product_id, other_product_id)), 0,
  'deleting a product removes its conflicts');

select * from finish();
rollback;
