-- record_sale: relative stock decrement through 'sale' stock movements,
-- idempotent retry, oversell alerts, and a variant product's stock staying the
-- sum of its variants.
begin;
create extension if not exists pgtap with schema extensions;
select plan(46);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner-a@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'owner-b@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
do $$ begin
  perform create_shop('{"id":"shop-b","name":"Shop B","type":"general","allow_oversell":1}');
end $$;
insert into product (id, profile_id, name) values ('pb1', 'shop-b', 'Pen');
insert into product (id, profile_id, name) values ('pb2', 'shop-b', 'Shirt');
insert into product_variant (id, product_id, profile_id, size) values ('vb1', 'pb2', 'shop-b', 'M');
insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason) values
  ('mb1', 'shop-b', 'pb1', null, 1, 'initial'), ('mb2', 'shop-b', 'pb2', 'vb1', 2, 'initial');
insert into customer (id, profile_id, name) values ('cb1', 'shop-b', 'Bea');

set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
do $$ begin
  perform create_shop('{"id":"shop-a","name":"Shop A","type":"shoes","variant_support":1}');
end $$;
insert into product (id, profile_id, name) values ('p1', 'shop-a', 'Socks');
-- A product with variants: the total is their sum (3 + 2).
insert into product (id, profile_id, name) values ('p2', 'shop-a', 'Sneaker');
insert into product_variant (id, product_id, profile_id, size) values
  ('v1', 'p2', 'shop-a', '42'),
  ('v2', 'p2', 'shop-a', '43');
insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason) values
  ('m1', 'shop-a', 'p1', null, 10, 'initial'),
  ('m2', 'shop-a', 'p2', 'v1', 3, 'initial'),
  ('m3', 'shop-a', 'p2', 'v2', 2, 'initial');
select is((select stock_qty from product where id = 'p2'), 5::bigint,
  'initial movements of the variants set the product total to their sum');
insert into customer (id, profile_id, name) values ('ca1', 'shop-a', 'Asha');

-- Two sales of the same product, recorded by two devices.
select is(
  record_sale(
    '{"id":"s1","profile_id":"shop-a","created_at":"2026-11-22T09:00:00.000Z","subtotal_minor":300,"total_minor":300}',
    '[{"id":"s1i1","product_id":"p1","product_name":"Socks","qty":3,"unit_price_minor":100}]'),
  '{"sale_id":"s1","duplicate":false,"stock_alerts":0}'::jsonb,
  'first sale is recorded');
select is((select stock_qty from product where id = 'p1'), 7::bigint, 'first sale takes 3 off stock');
select results_eq(
  $$select id, product_id, delta, reason, sale_id from stock_movement where sale_id = 's1'$$,
  $$values ('sale:s1i1'::text, 'p1'::text, -3::bigint, 'sale'::text, 's1'::text)$$,
  'the sale is recorded as one stock movement per item');
select is(
  record_sale(
    '{"id":"s2","profile_id":"shop-a","total_minor":400}',
    '[{"id":"s2i1","product_id":"p1","product_name":"Socks","qty":4,"unit_price_minor":100}]') ->> 'duplicate',
  'false', 'second sale is recorded');
select is((select stock_qty from product where id = 'p1'), 3::bigint,
  'second sale decrements relative to the first');
select is((select created_at from sale where id = 's1'), '2026-11-22T09:00:00.000Z',
  'the device''s sale time is kept');
select matches((select created_at from sale where id = 's2'),
  '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$', 'a missing sale time defaults to db_time format');

-- A retried upload of s1 changes nothing.
select is(
  record_sale(
    '{"id":"s1","profile_id":"shop-a","total_minor":300}',
    '[{"id":"s1i1","product_id":"p1","product_name":"Socks","qty":3,"unit_price_minor":100}]'),
  '{"sale_id":"s1","duplicate":true,"stock_alerts":0}'::jsonb,
  'retry is reported as a duplicate');
select is((select stock_qty from product where id = 'p1'), 3::bigint, 'retry does not decrement again');
select is((select count(*)::int from sale_item where sale_id = 's1'), 1, 'retry adds no items');
select is((select count(*)::int from sale), 2, 'retry adds no sale');
select is((select count(*)::int from stock_movement where sale_id = 's1'), 1, 'retry adds no movement');

-- A sale movement the device already uploaded under the item's id is not
-- applied a second time by record_sale.
insert into stock_movement (id, profile_id, product_id, delta, reason)
  values ('sale:s13i1', 'shop-a', 'p1', -1, 'sale');
select is((select stock_qty from product where id = 'p1'), 2::bigint, 'the uploaded movement is applied');
do $$ begin
  perform record_sale('{"id":"s13","profile_id":"shop-a"}',
    '[{"id":"s13i1","product_id":"p1","product_name":"Socks","qty":1}]');
end $$;
select is((select stock_qty from product where id = 'p1'), 2::bigint, '... and not again by record_sale');

-- Variant sale decrements the variant and the product total.
select lives_ok($$select record_sale(
    '{"id":"s3","profile_id":"shop-a"}',
    '[{"id":"s3i1","product_id":"p2","product_name":"Sneaker","variant_id":"v1","qty":2}]')$$,
  'variant sale is recorded');
select is((select stock_qty from product_variant where id = 'v1'), 1::bigint, 'variant stock decremented');
select is((select stock_qty from product where id = 'p2'), 3::bigint, 'product total decremented once');

-- Oversell with allow_oversell = 0: sale accepted, alert written.
select is(
  record_sale(
    '{"id":"s4","profile_id":"shop-a"}',
    '[{"id":"s4i1","product_id":"p1","product_name":"Socks","qty":2},
      {"id":"s4i2","product_id":"p1","product_name":"Socks","qty":3}]') ->> 'stock_alerts',
  '1', 'oversell is accepted with one alert');
select is((select stock_qty from product where id = 'p1'), -3::bigint,
  'two lines of one product are both decremented');
select results_eq(
  $$select product_id, variant_id, sale_id, stock_after from stock_alert where sale_id = 's4'$$,
  $$values ('p1'::text, null::text, 's4'::text, -3::bigint)$$,
  'alert records the product and stock after the sale');

-- Variant oversell: the variant goes negative, the product total does not.
select is(
  record_sale(
    '{"id":"s5","profile_id":"shop-a"}',
    '[{"id":"s5i1","product_id":"p2","product_name":"Sneaker","variant_id":"v2","qty":3}]') ->> 'stock_alerts',
  '1', 'variant oversell gives one alert');
select results_eq(
  $$select product_id, variant_id, stock_after from stock_alert where sale_id = 's5'$$,
  $$values ('p2'::text, 'v2'::text, -1::bigint)$$,
  'alert names the variant');
select is((select stock_qty from product where id = 'p2'), 0::bigint,
  'product total is the variants'' sum (1 + -1)');

-- Items cannot point at another shop's product; the whole sale is rolled back.
select throws_ok($$select record_sale(
    '{"id":"s6","profile_id":"shop-a"}',
    '[{"id":"s6i1","product_id":"pb1","product_name":"Pen","qty":1}]')$$,
  '23503', null, 'item for another shop''s product is rejected');
select is_empty($$select 1 from sale where id = 's6'$$, 'rejected sale is not written');

-- A sale is never failed by a customer or variant that another device has
-- since deleted, or that does not belong to the shop or the item's product.
select is(
  record_sale(
    '{"id":"s7","profile_id":"shop-a","customer_id":"gone"}',
    '[{"id":"s7i1","product_id":"p1","product_name":"Socks","variant_id":"v1","qty":1}]') ->> 'duplicate',
  'false', 'sale with a missing customer and a foreign variant is accepted');
select is((select customer_id from sale where id = 's7'), null, 'missing customer is stored as null');
select is((select variant_id from sale_item where id = 's7i1'), null,
  'variant of another product is stored as null');
select is((select stock_qty from product where id = 'p1'), -4::bigint,
  'the product without variants is still decremented');
select is((select stock_qty from product_variant where id = 'v1'), 1::bigint, 'the other product''s variant is untouched');

-- Variants added and removed with stock: the total follows (0 + 4, then 0).
insert into product_variant (id, product_id, profile_id, size) values ('v3', 'p2', 'shop-a', '44');
insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason)
  values ('m4', 'shop-a', 'p2', 'v3', 4, 'initial');
select is((select stock_qty from product where id = 'p2'), 4::bigint, 'a new variant''s stock is added to the total');
delete from product_variant where id = 'v3';
select is((select stock_qty from product where id = 'p2'), 0::bigint, 'a deleted variant''s stock leaves the total');

-- A sale of the deleted variant is kept, changes no stock, and is flagged.
select is(
  record_sale(
    '{"id":"s9","profile_id":"shop-a"}',
    '[{"id":"s9i1","product_id":"p2","product_name":"Sneaker","variant_id":"v3","qty":1}]'),
  '{"sale_id":"s9","duplicate":false,"stock_alerts":1}'::jsonb,
  'sale of a deleted variant is accepted with one alert');
select is((select variant_id from sale_item where id = 's9i1'), null, 'deleted variant is stored as null');
select results_eq(
  $$select (select stock_qty from product where id = 'p2'),
           (select sum(stock_qty)::bigint from product_variant where product_id = 'p2')$$,
  $$values (0::bigint, 0::bigint)$$, 'no stock changes and the total is still the variants'' sum');
select results_eq(
  $$select product_id, variant_id, stock_after from stock_alert where sale_id = 's9'$$,
  $$values ('p2'::text, null::text, 0::bigint)$$,
  'alert names the product and its unchanged stock');

do $$ begin
  perform record_sale('{"id":"s10","profile_id":"shop-a","customer_id":"cb1"}', '[]');
  perform record_sale('{"id":"s11","profile_id":"shop-a","customer_id":"ca1"}', '[]');
end $$;
select is((select customer_id from sale where id = 's10'), null, 'another shop''s customer is stored as null');
select is((select customer_id from sale where id = 's11'), 'ca1', 'the shop''s own customer is kept');

-- An item without a variant for a product with variants is still accepted
-- (the device recorded it), changes no stock, and is flagged.
select is(
  record_sale(
    '{"id":"s12","profile_id":"shop-a"}',
    '[{"id":"s12i1","product_id":"p2","product_name":"Sneaker","qty":1}]') ->> 'stock_alerts',
  '1', 'variant product sold without a variant is accepted with one alert');
select results_eq(
  $$select (select stock_qty from product where id = 'p2'),
           (select sum(stock_qty)::bigint from product_variant where product_id = 'p2')$$,
  $$values (0::bigint, 0::bigint)$$, 'no stock changes and the total is still the variants'' sum');

-- items must be an array.
select throws_ok($$select record_sale('{"id":"s8","profile_id":"shop-a"}', '{}')$$,
  '22023', null, 'items must be a JSON array');

-- Oversell allowed: stock goes negative without an alert.
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
select is(
  record_sale(
    '{"id":"sb1","profile_id":"shop-b"}',
    '[{"id":"sb1i1","product_id":"pb1","product_name":"Pen","qty":4}]') ->> 'stock_alerts',
  '0', 'no alert when the shop allows oversells');
select is((select stock_qty from product where id = 'pb1'), -3::bigint, 'stock goes negative');
select is(
  record_sale(
    '{"id":"sb2","profile_id":"shop-b"}',
    '[{"id":"sb2i1","product_id":"pb2","product_name":"Shirt","qty":1}]') ->> 'stock_alerts',
  '1', 'a line that changes no stock is flagged even when oversells are allowed');
select is((select stock_qty from product where id = 'pb2'), 2::bigint, '... and the total stays the variant''s stock');

select * from finish();
rollback;
