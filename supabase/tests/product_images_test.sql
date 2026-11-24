-- Product images: the product-images bucket is private, limited to small
-- JPEGs, and a shop's files are visible and writable only to its members.
-- Every check is skipped when the Storage service is not installed (for
-- example under `supabase db start`); see the migration.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

create temp table storage_installed as
  select to_regclass('storage.buckets') is not null and to_regclass('storage.objects') is not null as ok;
grant select on storage_installed to authenticated;

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner-a@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'owner-b@example.com'),
  ('cccccccc-0000-0000-0000-000000000001', 'staff-a@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
do $$ begin perform create_shop('{"id":"shop-a","name":"Shop A","type":"shoes"}'); end $$;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
do $$ begin perform create_shop('{"id":"shop-b","name":"Shop B","type":"shoes"}'); end $$;
reset role;
insert into shop_member (profile_id, user_id, role)
values ('shop-a', 'cccccccc-0000-0000-0000-000000000001', 'staff');

-- The bucket: private, 1 MiB, JPEG only.
select case when (select ok from storage_installed) then results_eq(
  $$select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'product-images'$$,
  $$values (false, 1048576::bigint, array['image/jpeg'])$$,
  'bucket is private, 1 MiB, JPEG only')
else skip('storage not installed', 1) end;

-- Owner A adds a file under its shop.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
select case when (select ok from storage_installed) then lives_ok(
  $$insert into storage.objects (bucket_id, name) values ('product-images', 'shop-a/p1/one.jpg')$$,
  'owner can add an image to its shop')
else skip('storage not installed', 1) end;
select case when (select ok from storage_installed) then results_eq(
  $$select name from storage.objects where bucket_id = 'product-images'$$,
  array['shop-a/p1/one.jpg'], 'owner can read its image')
else skip('storage not installed', 1) end;
select case when (select ok from storage_installed) then throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('product-images', 'shop-b/p9/x.jpg')$$,
  '42501', null, 'owner cannot add an image to another shop')
else skip('storage not installed', 1) end;

-- Staff of shop A reads and adds.
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000000001"}';
select case when (select ok from storage_installed) then results_eq(
  $$select name from storage.objects where bucket_id = 'product-images'$$,
  array['shop-a/p1/one.jpg'], 'staff can read the shop''s image')
else skip('storage not installed', 1) end;
select case when (select ok from storage_installed) then lives_ok(
  $$insert into storage.objects (bucket_id, name) values ('product-images', 'shop-a/p2/two.jpg')$$,
  'staff can add an image')
else skip('storage not installed', 1) end;

-- Owner B (another shop) sees and changes nothing of shop A.
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';
select case when (select ok from storage_installed) then is_empty(
  $$select 1 from storage.objects where bucket_id = 'product-images'$$,
  'another shop sees no images')
else skip('storage not installed', 1) end;
select case when (select ok from storage_installed) then throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('product-images', 'shop-a/p3/planted.jpg')$$,
  '42501', null, 'another shop cannot add an image to shop A')
else skip('storage not installed', 1) end;
select case when (select ok from storage_installed) then results_eq(
  $$with d as (delete from storage.objects where name = 'shop-a/p1/one.jpg' returning 1) select count(*)::int from d$$,
  array[0], 'another shop cannot delete shop A''s image')
else skip('storage not installed', 1) end;

-- Nobody renames a file (that would move it into another shop); A can delete.
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}';
select case when (select ok from storage_installed) then results_eq(
  $$with u as (update storage.objects set name = 'shop-b/p1/one.jpg' where name = 'shop-a/p1/one.jpg' returning 1) select count(*)::int from u$$,
  array[0], 'an image cannot be renamed or moved')
else skip('storage not installed', 1) end;
select case when (select ok from storage_installed) then results_eq(
  $$with d as (delete from storage.objects where name = 'shop-a/p1/one.jpg' returning 1) select count(*)::int from d$$,
  array[1], 'owner can delete its image')
else skip('storage not installed', 1) end;

select * from finish();
rollback;
