-- create_shop, update_profile and the currency lock, the stock ledger and the
-- variant stock total, delete rules and column defaults.
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner-a@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'owner-b@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';

-- create_shop
select results_eq(
  $$select id, name, currency, currency_decimals, theme_color, allow_oversell
    from create_shop('{"id":"shop-a","name":"Shop A","type":"fashion","currency":"JPY","currency_decimals":0}')$$,
  $$values ('shop-a'::text, 'Shop A'::text, 'JPY'::text, 0::smallint, 4285293567::bigint, 0::smallint)$$,
  'create_shop applies given values over column defaults');
select results_eq(
  $$select role from shop_member where profile_id = 'shop-a'$$, array['owner'],
  'creator becomes the owner');
select matches((select created_at from business_profile where id = 'shop-a'),
  '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$', 'created_at default matches db_time format');
select is((create_shop('{"id":"shop-a","name":"Retry","type":"fashion"}')).name, 'Shop A',
  'retrying create_shop returns the existing shop');
select is((select count(*)::int from shop_member), 1, 'retry adds no membership');
select throws_ok($$select create_shop('{"id":"shop-c","name":"Bad","type":"cafe"}')$$,
  '23514', null, 'type CHECK still applies');

set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
select throws_ok($$select create_shop('{"id":"shop-a","name":"Taken","type":"general"}')$$,
  '23505', null, 'another user cannot take an existing shop id');
do $$ begin perform create_shop('{"id":"shop-b","name":"Shop B","type":"general"}'); end $$;
insert into product (id, profile_id, name, sku) values ('pb1', 'shop-b', 'Shirt', 'SKU-1');

-- update_profile and the currency lock
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
select results_eq(
  $$select currency, currency_decimals, name from update_profile('{"id":"shop-a","currency":"USD","currency_decimals":2}')$$,
  $$values ('USD'::text, 2::smallint, 'Shop A'::text)$$,
  'currency can change while the shop is empty; omitted columns are kept');
select is((update_profile('{"id":"shop-a","created_at":"2000-01-01T00:00:00.000Z"}')).created_at,
  (select created_at from business_profile where id = 'shop-a'), 'update_profile ignores created_at');

insert into product (id, profile_id, name, sku, barcode) values ('p1', 'shop-a', 'Shirt', 'SKU-1', '890001');
select throws_ok($$select update_profile('{"id":"shop-a","currency":"EUR"}')$$,
  '23514', 'Currency is locked once products or sales exist', 'currency locked once a product exists');
select throws_ok($$select update_profile('{"id":"shop-a","currency_decimals":3}')$$,
  '23514', null, 'currency_decimals locked once a product exists');
select throws_ok($$update business_profile set currency = 'EUR' where id = 'shop-a'$$,
  '23514', null, 'direct update is locked too');
select is((update_profile('{"id":"shop-a","name":"Shop A2","allow_oversell":1,"currency":"USD"}')).name,
  'Shop A2', 'other fields still update (unchanged currency allowed)');

update product set archived = 1 where id = 'p1';
select throws_ok($$select update_profile('{"id":"shop-a","currency":"EUR"}')$$,
  '23514', null, 'archived products still lock the currency');

-- A sale alone locks it as well.
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
delete from product where id = 'pb1';
do $$ begin perform record_sale('{"id":"sb1","profile_id":"shop-b"}', '[]'); end $$;
select throws_ok($$select update_profile('{"id":"shop-b","currency":"EUR"}')$$,
  '23514', null, 'a sale locks the currency');
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';

-- Stock ledger: stock changes only through stock_movement.
insert into product (id, profile_id, name, stock_qty) values ('p3', 'shop-a', 'No codes', 50);
select is((select stock_qty from product where id = 'p3'), 0::bigint,
  'a client-set stock_qty on insert is ignored');
insert into product (id, profile_id, name) values ('p4', 'shop-a', 'Boots');
insert into product_variant (id, product_id, profile_id, size, stock_qty) values
  ('v1', 'p4', 'shop-a', 'S', 9), ('v2', 'p4', 'shop-a', 'M', 9);
insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason) values
  ('m1', 'shop-a', 'p4', 'v1', 1, 'initial'), ('m2', 'shop-a', 'p4', 'v2', 2, 'initial');
select results_eq(
  $$select stock_qty from product_variant where product_id = 'p4' order by id$$,
  $$values (1::bigint), (2::bigint)$$, 'variants start at 0 and take their initial movements');
select is((select stock_qty from product where id = 'p4'), 3::bigint,
  'the product total is its variants'' sum (1 + 2)');

insert into stock_movement (id, profile_id, product_id, delta, reason) values ('m3', 'shop-a', 'p3', 5, 'restock');
select is((select stock_qty from product where id = 'p3'), 5::bigint, 'a restock adds to a plain product');
insert into stock_movement (id, profile_id, product_id, delta, reason) values ('m3', 'shop-a', 'p3', 5, 'restock')
  on conflict (id) do nothing;
select is((select stock_qty from product where id = 'p3'), 5::bigint, 'a retried movement is not applied again');
insert into stock_movement (id, profile_id, product_id, delta, reason) values ('m4', 'shop-a', 'p3', -7, 'correction');
select results_eq(
  $$select (select stock_qty from product where id = 'p3'),
           (select count(*)::int from stock_alert where movement_id = 'm4')$$,
  $$values (-2::bigint, 0)$$, 'stock can go negative, without an alert when oversells are allowed');

-- Direct stock writes, including PowerSync-style upserts, are ignored.
update product set stock_qty = 100 where id = 'p3';
update product_variant set stock_qty = 100 where id = 'v1';
insert into product (id, profile_id, name, stock_qty) values ('p4', 'shop-a', 'Boots', 100)
  on conflict (id) do update set name = excluded.name, stock_qty = excluded.stock_qty;
select results_eq(
  $$select (select stock_qty from product where id = 'p3'),
           (select stock_qty from product_variant where id = 'v1'),
           (select stock_qty from product where id = 'p4')$$,
  $$values (-2::bigint, 1::bigint, 3::bigint)$$, 'clients cannot set stock_qty directly');
select throws_ok($$update stock_movement set delta = 100 where id = 'm3'$$,
  '42501', null, 'a movement cannot be updated');
select throws_ok($$delete from stock_movement where id = 'm3'$$,
  '42501', null, 'a movement cannot be deleted');

-- Movements that cannot be applied are kept, change nothing, and are flagged.
insert into stock_movement (id, profile_id, product_id, delta, reason) values ('m5', 'shop-a', 'p4', 4, 'restock');
select results_eq(
  $$select product_id, variant_id, stock_after from stock_alert where movement_id = 'm5'$$,
  $$values ('p4'::text, null::text, 3::bigint)$$,
  'a movement without a variant on a variant product is flagged');
select results_eq(
  $$select (select stock_qty from product where id = 'p4'),
           (select sum(stock_qty)::bigint from product_variant where product_id = 'p4')$$,
  $$values (3::bigint, 3::bigint)$$, '... and the total is still the variants'' sum');
insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason)
  values ('m6', 'shop-a', 'p3', 'v1', 1, 'restock');
select results_eq(
  $$select (select stock_qty from product where id = 'p3'),
           (select stock_qty from product_variant where id = 'v1'),
           (select count(*)::int from stock_alert where movement_id = 'm6')$$,
  $$values (-2::bigint, 1::bigint, 1)$$, 'a variant of another product changes nothing and is flagged');
insert into stock_movement (id, profile_id, product_id, delta, reason) values ('m7', 'shop-a', 'nope', 1, 'restock');
select results_eq(
  $$select (select count(*)::int from stock_movement where id = 'm7'),
           (select count(*)::int from stock_alert where movement_id = 'm7')$$,
  $$values (1, 0)$$, 'a movement for an unknown product is kept and changes nothing');

-- Moving a variant recomputes both products: p5 becomes v3's stock, p4 drops it.
insert into product (id, profile_id, name) values ('p5', 'shop-a', 'Sandals');
insert into stock_movement (id, profile_id, product_id, delta, reason) values ('m8', 'shop-a', 'p5', 7, 'initial');
insert into product_variant (id, product_id, profile_id, size) values ('v3', 'p4', 'shop-a', 'L');
insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason)
  values ('m9', 'shop-a', 'p4', 'v3', 4, 'initial');
select is((select stock_qty from product where id = 'p4'), 7::bigint, 'a new variant adds to the total (1 + 2 + 4)');
update product_variant set product_id = 'p5' where id = 'v3';
select results_eq(
  $$select (select stock_qty from product where id = 'p4'), (select stock_qty from product where id = 'p5')$$,
  $$values (3::bigint, 4::bigint)$$, 'a moved variant leaves the old total and makes the new one');
delete from product_variant where id = 'v3';
select is((select stock_qty from product where id = 'p5'), 0::bigint, 'removing the last variant leaves 0');

-- Variant product to plain product: delete the variants in either order
-- (total 0), then a 'conversion' movement with the stock the user typed.
insert into product (id, profile_id, name) values ('p6', 'shop-a', 'Caps'), ('p7', 'shop-a', 'Hats');
insert into product_variant (id, product_id, profile_id, size) values
  ('v6a', 'p6', 'shop-a', 'S'), ('v6b', 'p6', 'shop-a', 'M'),
  ('v7a', 'p7', 'shop-a', 'S'), ('v7b', 'p7', 'shop-a', 'M');
insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason) values
  ('m10', 'shop-a', 'p6', 'v6a', 3, 'initial'), ('m11', 'shop-a', 'p6', 'v6b', 2, 'initial'),
  ('m12', 'shop-a', 'p7', 'v7a', 3, 'initial'), ('m13', 'shop-a', 'p7', 'v7b', 2, 'initial');
delete from product_variant where id = 'v6a';
delete from product_variant where id = 'v6b';
delete from product_variant where id = 'v7b';
delete from product_variant where id = 'v7a';
select results_eq(
  $$select (select stock_qty from product where id = 'p6'), (select stock_qty from product where id = 'p7')$$,
  $$values (0::bigint, 0::bigint)$$, 'deleting all variants leaves 0 whatever the order');
insert into stock_movement (id, profile_id, product_id, delta, reason) values
  ('m14', 'shop-a', 'p6', 8, 'conversion'), ('m15', 'shop-a', 'p7', 8, 'conversion');
insert into stock_movement (id, profile_id, product_id, delta, reason) values
  ('m14', 'shop-a', 'p6', 8, 'conversion'), ('m15', 'shop-a', 'p7', 8, 'conversion')
  on conflict (id) do nothing;
select results_eq(
  $$select (select stock_qty from product where id = 'p6'), (select stock_qty from product where id = 'p7')$$,
  $$values (8::bigint, 8::bigint)$$, 'conversion ends at the typed stock in either order, retried or not');

-- A restock queued offline for a variant since deleted is accepted and flagged.
insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason)
  values ('m16', 'shop-a', 'p6', 'v6a', 5, 'restock');
select results_eq(
  $$select product_id, variant_id, stock_after from stock_alert where movement_id = 'm16'$$,
  $$values ('p6'::text, null::text, 8::bigint)$$,
  'a restock of a deleted variant is flagged and changes no stock');

-- Deletes: a sold product cannot be deleted; deleting the shop removes everything.
do $$ begin
  perform record_sale('{"id":"s1","profile_id":"shop-a"}',
    '[{"id":"s1i1","product_id":"p4","product_name":"Boots","variant_id":"v1","qty":1}]');
end $$;
select throws_ok($$delete from product where id = 'p4'$$, '23503', null, 'a sold product cannot be deleted');
delete from product_variant where id = 'v1';
select is((select variant_id from sale_item where id = 's1i1'), null, 'deleting a variant clears sale_item.variant_id');
select is((select stock_qty from product where id = 'p4'), 2::bigint, 'the total is the remaining variant''s stock');
select is((select profile_id from sale_item where id = 's1i1'), 'shop-a', '... and keeps its shop');
reset role;
delete from business_profile where id = 'shop-a';
select is(
  (select count(*)::int from product where profile_id = 'shop-a')
  + (select count(*)::int from sale where profile_id = 'shop-a')
  + (select count(*)::int from sale_item where profile_id = 'shop-a')
  + (select count(*)::int from product_variant where profile_id = 'shop-a')
  + (select count(*)::int from stock_movement where profile_id = 'shop-a')
  + (select count(*)::int from shop_member where profile_id = 'shop-a'),
  0, 'deleting a shop cascades to all its rows');

select * from finish();
rollback;
