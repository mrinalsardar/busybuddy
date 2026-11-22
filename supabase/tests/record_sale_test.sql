-- record_sale: relative stock decrement, idempotent retry, oversell alerts.
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner-a@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'owner-b@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
do $$ begin
  perform create_shop('{"id":"shop-b","name":"Shop B","type":"general","allow_oversell":1}');
end $$;
insert into product (id, profile_id, name, stock_qty) values ('pb1', 'shop-b', 'Pen', 1);

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

-- A variant must belong to the item's product.
select throws_ok($$select record_sale(
    '{"id":"s7","profile_id":"shop-a"}',
    '[{"id":"s7i1","product_id":"p1","product_name":"Socks","variant_id":"v1","qty":1}]')$$,
  '23503', null, 'variant of a different product is rejected');

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
