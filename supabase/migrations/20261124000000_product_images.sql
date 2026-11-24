-- Product images: a private Storage bucket and the access rules for it.
--
-- PowerSync syncs rows, not files. product.image_path (already in the schema)
-- holds the object path '<profile_id>/<product_id>/<uuid>.jpg' of a file in
-- this bucket. The first path segment is the shop, so the rules below are the
-- same membership check as the table policies. Devices upload and delete the
-- files themselves (lib/core/images/product_image_store.dart); the server never
-- deletes a file, because Storage does not allow deleting from storage.objects
-- in SQL.
--
-- Limits, enforced by Storage whatever the client does: 1 MiB per file, JPEG
-- only. The app sends JPEGs of at most 1024 px (about 100-200 KB).
--
-- The storage schema exists only when the Storage service is installed: always
-- on a hosted project, and in a local stack that runs it. Without it (for
-- example `supabase db start`, which starts only Postgres) this migration
-- does nothing, and a later `supabase db reset` with Storage applies it.

do $migration$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice 'Storage is not installed: product-images bucket and policies skipped';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('product-images', 'product-images', false, 1048576, array['image/jpeg'])
  on conflict (id) do update
    set public = false,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

  -- Members of a shop read, add and delete that shop's images. There is no
  -- update policy: an image is never overwritten, a replacement is a new path.
  -- Nothing is granted to anon.
  create policy product_images_select on storage.objects
    for select to authenticated
    using (
      bucket_id = 'product-images'
      and (storage.foldername(name))[1] in (select private.my_shop_ids())
    );
  create policy product_images_insert on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'product-images'
      and (storage.foldername(name))[1] in (select private.my_shop_ids())
    );
  create policy product_images_delete on storage.objects
    for delete to authenticated
    using (
      bucket_id = 'product-images'
      and (storage.foldername(name))[1] in (select private.my_shop_ids())
    );
end
$migration$;
