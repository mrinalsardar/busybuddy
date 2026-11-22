-- record_sale: relative stock decrement, idempotent retry, oversell alerts.
begin;
create extension if not exists pgtap with schema extensions;
select plan(36);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner-a@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'owner-b@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
do $$ begin
  perform create_shop('{"id":"shop-b","name":"Shop B","type":"general","allow_oversell":1}');
end $$;
insert into product (id, profile_id, name, stock_qty) values ('pb1', 'shop-b', 'Pen', 1);
insert into customer (id, profile_id, name) values ('cb1', 'shop-b', 'Bea');

set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
do $$ begin
  perform create_shop('{"id":"shop-a","name":"Shop A","type":"shoes","variant_support":1}');
end $$;
insert into product (id, profile_id, name, stock_qty) values ('p1', 'shop-a', 'Socks', 10);
-- A product with variants: product stock is the variants' total.
insert into product (id, profile_id, name, stock_qty) values ('p2', 'shop-a', 'Sneaker', 5);
insert into product_variant (id, product_id, profile_id, size, stock_qty) values
  ('v1', 'p2', 'shop-a', '42', 3),
  ('v2', 'p2', 'shop-a', '43', 2);
insert into customer (id, profile_id, name) values ('ca1', 'shop-a', 'Asha');

-- Two sales of the same product, recorded by two devices.
select is(
  record_sale(
    '{"id":"s1","profile_id":"shop-a","created_at":"2026-11-22T09:00:00.000Z","subtotal_minor":300,"total_minor":300}',
    '[{"id":"s1i1","product_id":"p1","product_name":"Socks","qty":3,"unit_price_minor":100}]'),
  '{"sale_id":"s1","duplicate":false,"stock_alerts":0}'::jsonb,
  'first sale is recorded');
select is((select stock_qty from product where id = 'p1'), 7::bigint, 'first sale takes 3 off stock');
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

-- Variant sale decrements the variant and the product total.
select lives_ok($$select record_sale(
    '{"id":"s3","profile_id":"shop-a"}',
    '[{"id":"s3i1","product_id":"p2","product_name":"Sneaker","variant_id":"v1","qty":2}]')$$,
  'variant sale is recorded');
select is((select stock_qty from product_variant where id = 'v1'), 1::bigint, 'variant stock decremented');
select is((select stock_qty from product where id = 'p2'), 3::bigint, 'product total decremented');

-- Oversell with allow_oversell = 0: sale accepted, alert written.
select is(
  record_sale(
    '{"id":"s4","profile_id":"shop-a"}',
    '[{"id":"s4i1","product_id":"p1","product_name":"Socks","qty":2},
      {"id":"s4i2","product_id":"p1","product_name":"Socks","qty":3}]') ->> 'stock_alerts',
  '1', 'oversell is accepted with one alert');
select is((select stock_qty from product where id = 'p1'), -2::bigint,
  'two lines of one product are both decremented');
select results_eq(
  $$select product_id, variant_id, sale_id, stock_after from stock_alert where sale_id = 's4'$$,
  $$values ('p1'::text, null::text, 's4'::text, -2::bigint)$$,
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
select is((select stock_qty from product where id = 'p2'), 0::bigint, 'product total follows the variant');

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
select is((select stock_qty from product where id = 'p1'), -3::bigint, 'the product total is still decremented');
select is((select stock_qty from product_variant where id = 'v1'), 1::bigint, 'the other product''s variant is untouched');

insert into product_variant (id, product_id, profile_id, size, stock_qty) values ('v3', 'p2', 'shop-a', '44', 0);
delete from product_variant where id = 'v3';
select is(
  record_sale(
    '{"id":"s9","profile_id":"shop-a"}',
    '[{"id":"s9i1","product_id":"p2","product_name":"Sneaker","variant_id":"v3","qty":1}]') ->> 'duplicate',
  'false', 'sale of a deleted variant is accepted');
select is((select variant_id from sale_item where id = 's9i1'), null, 'deleted variant is stored as null');
select is((select stock_qty from product where id = 'p2'), -1::bigint, 'the product total is decremented');

do $$ begin
  perform record_sale('{"id":"s10","profile_id":"shop-a","customer_id":"cb1"}', '[]');
  perform record_sale('{"id":"s11","profile_id":"shop-a","customer_id":"ca1"}', '[]');
end $$;
select is((select customer_id from sale where id = 's10'), null, 'another shop''s customer is stored as null');
select is((select customer_id from sale where id = 's11'), 'ca1', 'the shop''s own customer is kept');

-- An item without a variant for a product with variants is still accepted
-- (the device recorded it), and decrements only the product total.
select is(
  record_sale(
    '{"id":"s12","profile_id":"shop-a"}',
    '[{"id":"s12i1","product_id":"p2","product_name":"Sneaker","qty":1}]') ->> 'duplicate',
  'false', 'variant product sold without a variant is accepted');
select results_eq(
  $$select (select stock_qty from product where id = 'p2'),
           (select sum(stock_qty)::bigint from product_variant where product_id = 'p2')$$,
  $$values (-2::bigint, 0::bigint)$$, 'only the product total changes');

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

select * from finish();
rollback;
