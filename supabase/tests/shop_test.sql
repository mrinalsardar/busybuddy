-- create_shop, update_profile and the currency lock, adjust_stock and the
-- variant stock total, delete rules and column defaults.
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

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

-- adjust_stock
insert into product (id, profile_id, name) values ('p3', 'shop-a', 'No codes');
insert into product (id, profile_id, name) values ('p4', 'shop-a', 'Boots');
insert into product_variant (id, product_id, profile_id, size, stock_qty) values
  ('v1', 'p4', 'shop-a', 'S', 1), ('v2', 'p4', 'shop-a', 'M', 2);
select is((select stock_qty from product where id = 'p4'), 3::bigint,
  'the product total is its variants'' sum (1 + 2)');
select is(adjust_stock('p3', null, 5), '{"product_stock_qty":5,"variant_stock_qty":null}'::jsonb,
  'adjust_stock adds to a plain product');
select is(adjust_stock('p3', null, -7) ->> 'product_stock_qty', '-2', 'adjust_stock can go negative');
select is(adjust_stock('p4', 'v2', -1), '{"product_stock_qty":2,"variant_stock_qty":1}'::jsonb,
  'adjust_stock changes the variant and the product total');
select throws_ok($$select adjust_stock('p3', 'v1', 1)$$,
  'P0002', null, 'variant must belong to the product');
select throws_ok($$select adjust_stock('p4', null, 1)$$,
  '22023', null, 'a product with variants needs a variant_id');
select is((select stock_qty from product where id = 'p4'), 2::bigint, 'refused adjust leaves the total alone');
select is((select stock_qty from product where id = 'p3'), -2::bigint, 'failed adjust changes nothing');

-- Moving a variant recomputes both products: p5 becomes v3's stock, p4 drops it.
insert into product (id, profile_id, name, stock_qty) values ('p5', 'shop-a', 'Sandals', 7);
insert into product_variant (id, product_id, profile_id, size, stock_qty) values ('v3', 'p4', 'shop-a', 'L', 4);
select is((select stock_qty from product where id = 'p4'), 6::bigint, 'a new variant adds to the total (1 + 1 + 4)');
update product_variant set product_id = 'p5' where id = 'v3';
select results_eq(
  $$select (select stock_qty from product where id = 'p4'), (select stock_qty from product where id = 'p5')$$,
  $$values (2::bigint, 4::bigint)$$, 'a moved variant leaves the old total and makes the new one');
-- Removing every variant leaves 0 (the sum of no variants) in either delete
-- order; then the product is stocked as a plain product.
delete from product_variant where id = 'v3';
select is((select stock_qty from product where id = 'p5'), 0::bigint, 'removing the last variant leaves 0');
insert into product (id, profile_id, name) values ('p6', 'shop-a', 'Caps'), ('p7', 'shop-a', 'Hats');
insert into product_variant (id, product_id, profile_id, size, stock_qty) values
  ('v6a', 'p6', 'shop-a', 'S', 3), ('v6b', 'p6', 'shop-a', 'M', 2),
  ('v7a', 'p7', 'shop-a', 'S', 3), ('v7b', 'p7', 'shop-a', 'M', 2);
delete from product_variant where id = 'v6a';
delete from product_variant where id = 'v6b';
delete from product_variant where id = 'v7b';
delete from product_variant where id = 'v7a';
select results_eq(
  $$select (select stock_qty from product where id = 'p6'), (select stock_qty from product where id = 'p7')$$,
  $$values (0::bigint, 0::bigint)$$, 'deleting all variants leaves 0 whatever the order');
select is(adjust_stock('p6', null, 8) ->> 'product_stock_qty', '8',
  'a product with no variants left takes the entered stock');
select is(adjust_stock('p7', null, 8) ->> 'product_stock_qty', '8',
  '... in either delete order');
select is((select stock_qty from product where id = 'p6'), 8::bigint, 'the entered stock is stored');

-- Deletes: a sold product cannot be deleted; deleting the shop removes everything.
do $$ begin
  perform record_sale('{"id":"s1","profile_id":"shop-a"}',
    '[{"id":"s1i1","product_id":"p4","product_name":"Boots","variant_id":"v1","qty":1}]');
end $$;
select throws_ok($$delete from product where id = 'p4'$$, '23503', null, 'a sold product cannot be deleted');
delete from product_variant where id = 'v1';
select is((select variant_id from sale_item where id = 's1i1'), null, 'deleting a variant clears sale_item.variant_id');
select is((select stock_qty from product where id = 'p4'), 1::bigint, 'the total is the remaining variant''s stock');
select is((select profile_id from sale_item where id = 's1i1'), 'shop-a', '... and keeps its shop');
reset role;
delete from business_profile where id = 'shop-a';
select is(
  (select count(*)::int from product where profile_id = 'shop-a')
  + (select count(*)::int from sale where profile_id = 'shop-a')
  + (select count(*)::int from sale_item where profile_id = 'shop-a')
  + (select count(*)::int from product_variant where profile_id = 'shop-a')
  + (select count(*)::int from shop_member where profile_id = 'shop-a'),
  0, 'deleting a shop cascades to all its rows');

select * from finish();
rollback;
