-- BusyBuddy server schema: the Postgres side that devices sync against
-- through PowerSync. Ported from lib/core/db/database_helper.dart (_onCreate).
--
-- Conventions kept from the on-device schema:
--   * ids are text (the app generates UUID strings);
--   * money columns end in _minor and hold integer minor units (bigint);
--   * 0/1 flags are smallint;
--   * timestamps are text, UTC ISO-8601 with milliseconds and a Z
--     ("2026-11-10T08:30:00.123Z", see lib/core/db/db_time.dart), so they sort
--     and compare as strings; calendar dates are 'YYYY-MM-DD' text.
--
-- Every shop-owned table carries profile_id (the business_profile row), because
-- PowerSync sync rules and RLS policies cannot join. Child rows reference their
-- parent through composite (id, profile_id) foreign keys, so a row can never
-- point at another shop's data.

-- Helpers ---------------------------------------------------------------------

-- Matches toDbTime in lib/core/db/db_time.dart.
create function public.to_db_time(t timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
$$;

-- Not exposed through the API: holds the membership checks used by policies.
create schema private;

-- Tables ----------------------------------------------------------------------

create table public.business_profile (
  id text primary key,
  name text not null,
  type text not null check (type in ('shoes', 'fashion', 'grocery', 'general')),
  currency text not null default 'INR',
  tax_label text not null default 'GST',
  -- ARGB colour; 0xFF6C63FF does not fit in a 32-bit signed integer.
  theme_color bigint not null default 4285293567,
  variant_support smallint not null default 0,
  expiry_tracking smallint not null default 0,
  -- 1: a sale may take stock below 0. 0: oversells are flagged in stock_alert.
  allow_oversell smallint not null default 0 check (allow_oversell in (0, 1)),
  -- Fixed once the shop has products or sales: amounts are stored in minor
  -- units, so changing it would rescale every stored amount.
  currency_decimals smallint not null default 2 check (currency_decimals between 0 and 3),
  created_at text not null default public.to_db_time(now())
);

create table public.shop_member (
  profile_id text not null references public.business_profile (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'staff')),
  created_at text not null default public.to_db_time(now()),
  primary key (profile_id, user_id)
);

create table public.shop_invite (
  code text primary key,
  profile_id text not null references public.business_profile (id) on delete cascade,
  created_by uuid references auth.users (id) on delete set null,
  expires_at text not null,
  used_by uuid references auth.users (id) on delete set null,
  used_at text
);

create table public.product (
  id text primary key,
  profile_id text not null references public.business_profile (id) on delete cascade,
  name text not null,
  sku text,
  barcode text,
  price_minor bigint not null default 0 check (price_minor >= 0),
  cost_price_minor bigint not null default 0 check (cost_price_minor >= 0),
  category text,
  -- Changed only through stock_movement (clients' writes are ignored, see
  -- stock_qty_guard). For a product with variants this is the sum of the
  -- variants' stock, kept by the product_variant_stock trigger. No CHECK >= 0:
  -- it goes negative on oversells.
  stock_qty bigint not null default 0,
  low_stock_threshold integer not null default 5 check (low_stock_threshold >= 0),
  expiry_date text,
  image_path text,
  archived smallint not null default 0 check (archived in (0, 1)),
  created_at text not null default public.to_db_time(now()),
  updated_at text not null default public.to_db_time(now()),
  unique (id, profile_id)
);

create table public.product_variant (
  id text primary key,
  product_id text not null,
  profile_id text not null references public.business_profile (id) on delete cascade,
  size text,
  color text,
  -- Changed only through stock_movement, like product.stock_qty.
  stock_qty bigint not null default 0,
  created_at text not null default public.to_db_time(now()),
  unique (id, product_id),
  foreign key (product_id, profile_id) references public.product (id, profile_id) on delete cascade
);

create table public.customer (
  id text primary key,
  profile_id text not null references public.business_profile (id) on delete cascade,
  name text not null,
  phone text,
  email text,
  created_at text not null default public.to_db_time(now()),
  unique (id, profile_id)
);

create table public.sale (
  id text primary key,
  profile_id text not null references public.business_profile (id) on delete cascade,
  customer_id text,
  created_at text not null default public.to_db_time(now()),
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  tax_amount_minor bigint not null default 0 check (tax_amount_minor >= 0),
  discount_minor bigint not null default 0 check (discount_minor >= 0),
  total_minor bigint not null default 0 check (total_minor >= 0),
  payment_method text not null default 'cash',
  unique (id, profile_id),
  foreign key (customer_id, profile_id) references public.customer (id, profile_id)
    on delete set null (customer_id)
);

create table public.sale_item (
  id text primary key,
  sale_id text not null,
  profile_id text not null references public.business_profile (id) on delete cascade,
  product_id text not null,
  product_name text not null,
  variant_id text,
  qty bigint not null default 1 check (qty > 0),
  unit_price_minor bigint not null default 0 check (unit_price_minor >= 0),
  -- Cost at time of sale, so profit stays right after cost edits.
  cost_price_minor bigint not null default 0 check (cost_price_minor >= 0),
  foreign key (sale_id, profile_id) references public.sale (id, profile_id) on delete cascade,
  -- No ON DELETE action: a product that appears in a sale cannot be deleted
  -- (archive it instead). NO ACTION rather than RESTRICT so a profile delete,
  -- which cascades to both sale and product, still works.
  foreign key (product_id, profile_id) references public.product (id, profile_id),
  foreign key (variant_id, product_id) references public.product_variant (id, product_id)
    on delete set null (variant_id)
);

create table public.expense (
  id text primary key,
  profile_id text not null references public.business_profile (id) on delete cascade,
  amount_minor bigint not null default 0 check (amount_minor >= 0),
  category text,
  note text,
  -- Local calendar date, always set by the client (no server default: the
  -- server does not know the shop's time zone).
  date text not null,
  created_at text not null default public.to_db_time(now())
);

create table public.supplier (
  id text primary key,
  profile_id text not null references public.business_profile (id) on delete cascade,
  name text not null,
  contact text,
  email text,
  created_at text not null default public.to_db_time(now())
);

-- Append-only stock ledger: every stock change, from a sale, restock,
-- correction or the opening stock, is one row, applied exactly once by the
-- stock_movement_apply trigger. The id is generated by the client, so a retried
-- upload (insert ... on conflict (id) do nothing) changes nothing. A movement
-- is never rejected for stock reasons: one that cannot be applied is kept and
-- flagged in stock_alert. So variant_id, product_id and sale_id have no foreign
-- keys that could fail an upload.
create table public.stock_movement (
  id text primary key,
  profile_id text not null references public.business_profile (id) on delete cascade,
  product_id text not null,
  variant_id text,
  delta bigint not null,
  reason text not null check (reason in ('initial', 'restock', 'correction', 'sale', 'conversion')),
  -- Set by record_sale for reason 'sale'.
  sale_id text,
  created_by uuid default auth.uid(),
  created_at text not null default public.to_db_time(now())
);

-- Written by stock_movement_apply when a movement takes stock below zero while
-- the shop's allow_oversell is 0, and for every movement that changed no stock
-- (a variant that no longer exists, or no variant for a product that has
-- variants). The movement itself is always kept: a sale already happened on a
-- device that may have been offline.
create table public.stock_alert (
  id text primary key default gen_random_uuid()::text,
  profile_id text not null references public.business_profile (id) on delete cascade,
  product_id text not null,
  -- Set when the variant's stock went negative; null for a product, or for a
  -- movement that changed no stock.
  variant_id text,
  movement_id text not null references public.stock_movement (id) on delete cascade,
  -- The movement's sale, when it came from one.
  sale_id text,
  stock_after bigint not null,
  created_at text not null default public.to_db_time(now()),
  foreign key (product_id, profile_id) references public.product (id, profile_id) on delete cascade,
  foreign key (variant_id, product_id) references public.product_variant (id, product_id)
    on delete set null (variant_id),
  foreign key (sale_id, profile_id) references public.sale (id, profile_id) on delete cascade
);

-- Two active products of one shop with the same SKU or barcode. Devices create
-- products offline, so the server accepts duplicate codes rather than reject
-- an upload (which would block that device's upload queue), and flags them
-- here. Written by the product_code_conflicts trigger; resolved_at is set when
-- either product is archived or its code changes.
create table public.code_conflict (
  id text primary key default gen_random_uuid()::text,
  profile_id text not null references public.business_profile (id) on delete cascade,
  -- The product whose write created the duplicate.
  product_id text not null,
  -- The active product that already had the code.
  other_product_id text not null,
  field text not null check (field in ('sku', 'barcode')),
  value text not null,
  created_at text not null default public.to_db_time(now()),
  resolved_at text,
  foreign key (product_id, profile_id) references public.product (id, profile_id) on delete cascade,
  foreign key (other_product_id, profile_id) references public.product (id, profile_id) on delete cascade
);

-- Indexes ---------------------------------------------------------------------

create index idx_product_profile on public.product (profile_id);
create index idx_product_category on public.product (category);
create index idx_product_variant_product on public.product_variant (product_id);
create index idx_product_variant_profile on public.product_variant (profile_id);
create index idx_customer_profile on public.customer (profile_id);
create index idx_sale_profile on public.sale (profile_id);
create index idx_sale_created on public.sale (created_at);
create index idx_sale_customer on public.sale (customer_id);
create index idx_sale_item_sale on public.sale_item (sale_id);
create index idx_sale_item_profile on public.sale_item (profile_id);
create index idx_sale_item_product on public.sale_item (product_id);
create index idx_expense_profile on public.expense (profile_id);
create index idx_supplier_profile on public.supplier (profile_id);
create index idx_stock_movement_profile on public.stock_movement (profile_id);
create index idx_stock_movement_product on public.stock_movement (product_id);
create index idx_stock_alert_profile on public.stock_alert (profile_id);
create index idx_stock_alert_sale on public.stock_alert (sale_id);
create index idx_shop_member_user on public.shop_member (user_id);
create index idx_shop_invite_profile on public.shop_invite (profile_id);
create index idx_code_conflict_profile on public.code_conflict (profile_id);

-- Lookup of active products by code. Not unique: duplicates are flagged in
-- code_conflict instead of rejected (see product_code_conflicts).
create index idx_product_sku on public.product (profile_id, sku)
  where sku is not null and archived = 0;
create index idx_product_barcode on public.product (profile_id, barcode)
  where barcode is not null and archived = 0;

-- Membership checks -----------------------------------------------------------
-- security definer so policies on shop_member (and policies that consult it)
-- do not recurse through shop_member's own RLS.

create function private.my_shop_ids()
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select profile_id from public.shop_member where user_id = auth.uid()
$$;

create function private.is_shop_member(p_profile_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.shop_member
    where profile_id = p_profile_id and user_id = auth.uid()
  )
$$;

create function private.is_shop_owner(p_profile_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.shop_member
    where profile_id = p_profile_id and user_id = auth.uid() and role = 'owner'
  )
$$;

-- Currency lock ---------------------------------------------------------------
-- Mirrors ActiveProfileNotifier.updateProfile: currency and currency_decimals
-- cannot change once the shop has any product (archived included) or sale.
-- A trigger, so it holds for direct updates as well as update_profile.

create function private.enforce_currency_lock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.product where profile_id = old.id)
     or exists (select 1 from public.sale where profile_id = old.id) then
    raise exception 'Currency is locked once products or sales exist'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger business_profile_currency_lock
  before update of currency, currency_decimals on public.business_profile
  for each row
  when (old.currency is distinct from new.currency
        or old.currency_decimals is distinct from new.currency_decimals)
  execute function private.enforce_currency_lock();

-- Duplicate codes -------------------------------------------------------------
-- On a product write: resolve open code_conflict rows that the write ends (the
-- product is archived, or its code no longer matches), then flag each other
-- active product of the shop with the same non-null sku or barcode.

create function private.flag_code_conflicts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.code_conflict c
  set resolved_at = public.to_db_time(now())
  where c.profile_id = new.profile_id
    and c.resolved_at is null
    and new.id in (c.product_id, c.other_product_id)
    and (new.archived = 1
         or c.value is distinct from (case c.field when 'sku' then new.sku else new.barcode end));

  if new.archived = 1 then
    return null;
  end if;

  if new.sku is not null then
    -- Serialise writers of the same code, so two concurrent inserts still see
    -- each other.
    perform pg_advisory_xact_lock(hashtext(new.profile_id || ':sku:' || new.sku));
    insert into public.code_conflict (profile_id, product_id, other_product_id, field, value)
    select new.profile_id, new.id, p.id, 'sku', new.sku
    from public.product p
    where p.profile_id = new.profile_id and p.sku = new.sku and p.archived = 0
      and p.id <> new.id
      and not exists (
        select 1 from public.code_conflict c
        where c.profile_id = new.profile_id and c.resolved_at is null
          and c.field = 'sku' and c.value = new.sku
          and ((c.product_id = new.id and c.other_product_id = p.id)
               or (c.product_id = p.id and c.other_product_id = new.id)));
  end if;

  if new.barcode is not null then
    perform pg_advisory_xact_lock(hashtext(new.profile_id || ':barcode:' || new.barcode));
    insert into public.code_conflict (profile_id, product_id, other_product_id, field, value)
    select new.profile_id, new.id, p.id, 'barcode', new.barcode
    from public.product p
    where p.profile_id = new.profile_id and p.barcode = new.barcode and p.archived = 0
      and p.id <> new.id
      and not exists (
        select 1 from public.code_conflict c
        where c.profile_id = new.profile_id and c.resolved_at is null
          and c.field = 'barcode' and c.value = new.barcode
          and ((c.product_id = new.id and c.other_product_id = p.id)
               or (c.product_id = p.id and c.other_product_id = new.id)));
  end if;

  return null;
end;
$$;

create trigger product_code_conflicts
  after insert or update of sku, barcode, archived on public.product
  for each row
  execute function private.flag_code_conflicts();

-- Stock guard -----------------------------------------------------------------
-- Clients never set stock_qty: devices change stock concurrently, so an
-- absolute value would overwrite another device's change. A client write is
-- ignored rather than rejected (PowerSync uploads whole rows, and a rejected
-- upload would block the device's queue): an insert starts at 0, an update
-- keeps the old value. Only writes made by the stock triggers below (trigger
-- depth > 1) change it.

create function private.guard_stock_qty()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if pg_trigger_depth() = 1 then
    if tg_op = 'INSERT' then
      new.stock_qty := 0;
    else
      new.stock_qty := old.stock_qty;
    end if;
  end if;
  return new;
end;
$$;

create trigger product_stock_qty_guard
  before insert or update on public.product
  for each row
  execute function private.guard_stock_qty();

create trigger product_variant_stock_qty_guard
  before insert or update on public.product_variant
  for each row
  execute function private.guard_stock_qty();

-- Stock ledger ----------------------------------------------------------------
-- Applies a new stock_movement row once (a duplicate id never gets here). A
-- movement with a variant changes that variant (product_variant_stock then
-- updates the product); one without a variant changes a product that has no
-- variants. Never raises for stock reasons:
--   * a product not in the movement's shop: nothing applied, no alert (it
--     cannot reference the product);
--   * a variant that is not the product's (deleted, or the product is now
--     plain), or no variant for a product with variants: nothing applied, a
--     stock_alert with variant_id null and the product's stock;
--   * stock below zero while allow_oversell is 0: applied, and a stock_alert.

create function private.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allow_oversell smallint;
  v_variant text;
  v_stock bigint;
  v_sale text;
begin
  -- Serialise stock changes per shop (record_sale already holds this lock).
  select allow_oversell into v_allow_oversell
  from business_profile where id = new.profile_id
  for no key update;

  if not exists (
    select 1 from product p where p.id = new.product_id and p.profile_id = new.profile_id
  ) then
    return null;
  end if;

  if new.variant_id is not null then
    update product_variant v
    set stock_qty = v.stock_qty + new.delta
    where v.id = new.variant_id and v.product_id = new.product_id
    returning v.id, v.stock_qty into v_variant, v_stock;
  else
    perform 1 from product p where p.id = new.product_id for no key update;
    if not exists (select 1 from product_variant v where v.product_id = new.product_id) then
      update product p
      set stock_qty = p.stock_qty + new.delta,
          updated_at = to_db_time(now())
      where p.id = new.product_id
      returning p.stock_qty into v_stock;
    end if;
  end if;

  select s.id into v_sale from sale s
  where s.id = new.sale_id and s.profile_id = new.profile_id;

  if v_stock is null then
    insert into stock_alert (profile_id, product_id, variant_id, movement_id, sale_id, stock_after)
    select new.profile_id, p.id, null, new.id, v_sale, p.stock_qty
    from product p where p.id = new.product_id;
  elsif v_allow_oversell = 0 and v_stock < 0 then
    insert into stock_alert (profile_id, product_id, variant_id, movement_id, sale_id, stock_after)
    values (new.profile_id, new.product_id, v_variant, new.id, v_sale, v_stock);
  end if;
  return null;
end;
$$;

create trigger stock_movement_apply
  after insert on public.stock_movement
  for each row
  execute function private.apply_stock_movement();

-- Variant stock total ---------------------------------------------------------
-- A product with variants has stock_qty = the sum of its variants' stock_qty.
-- Recomputed on every variant insert, delete, stock change or move, for the
-- old and the new product. A product left with no variants gets 0 (the sum of
-- no variants); a 'conversion' movement then sets its stock as a plain product.
-- The product row is locked before the sum is read, so concurrent variant
-- changes of one product each see the other's committed stock.

create function private.sync_variant_product_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_products text[];
  v_product text;
begin
  if tg_op = 'INSERT' then
    v_products := array[new.product_id];
  elsif tg_op = 'DELETE' then
    v_products := array[old.product_id];
  else
    v_products := array[old.product_id, new.product_id];
  end if;
  for v_product in select distinct x from unnest(v_products) x loop
    perform 1 from public.product where id = v_product for no key update;
    update public.product p
    set stock_qty = (select coalesce(sum(v.stock_qty), 0) from public.product_variant v
                     where v.product_id = p.id),
        updated_at = public.to_db_time(now())
    where p.id = v_product;
  end loop;
  return null;
end;
$$;

create trigger product_variant_stock
  after insert or delete or update of stock_qty, product_id on public.product_variant
  for each row
  execute function private.sync_variant_product_stock();

-- Row-level security ----------------------------------------------------------

alter table public.business_profile enable row level security;
alter table public.shop_member enable row level security;
alter table public.shop_invite enable row level security;
alter table public.product enable row level security;
alter table public.product_variant enable row level security;
alter table public.customer enable row level security;
alter table public.sale enable row level security;
alter table public.sale_item enable row level security;
alter table public.expense enable row level security;
alter table public.supplier enable row level security;
alter table public.stock_movement enable row level security;
alter table public.stock_alert enable row level security;
alter table public.code_conflict enable row level security;

-- business_profile: members read, owners update. Created only by create_shop.
create policy business_profile_select on public.business_profile
  for select to authenticated
  using (id in (select private.my_shop_ids()));
create policy business_profile_update on public.business_profile
  for update to authenticated
  using (private.is_shop_owner(id))
  with check (private.is_shop_owner(id));

-- shop_member: members see their shop's member list. Written only by
-- create_shop and join_shop.
create policy shop_member_select on public.shop_member
  for select to authenticated
  using (profile_id in (select private.my_shop_ids()));

-- shop_invite: no policies; reached only through create_invite and join_shop.

-- Shop data: members of a shop read and write that shop's rows.
create policy product_member on public.product
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));
create policy product_variant_member on public.product_variant
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));
create policy customer_member on public.customer
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));
create policy sale_member on public.sale
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));
create policy sale_item_member on public.sale_item
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));
create policy expense_member on public.expense
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));
create policy supplier_member on public.supplier
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));
-- stock_movement is append-only: members read and insert, nobody updates or
-- deletes.
create policy stock_movement_select on public.stock_movement
  for select to authenticated
  using (profile_id in (select private.my_shop_ids()));
create policy stock_movement_insert on public.stock_movement
  for insert to authenticated
  with check (profile_id in (select private.my_shop_ids()));
create policy stock_alert_member on public.stock_alert
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));
create policy code_conflict_member on public.code_conflict
  for all to authenticated
  using (profile_id in (select private.my_shop_ids()))
  with check (profile_id in (select private.my_shop_ids()));

-- Privileges: nothing for anon; authenticated gets what the policies allow.
revoke all on all tables in schema public from anon, authenticated;
grant select, update on public.business_profile to authenticated;
grant select on public.shop_member to authenticated;
grant select, insert, update, delete on
  public.product, public.product_variant, public.customer, public.sale,
  public.sale_item, public.expense, public.supplier, public.stock_alert,
  public.code_conflict
  to authenticated;
grant select, insert on public.stock_movement to authenticated;

grant usage on schema private to authenticated;
revoke all on all functions in schema private from public, anon;
grant execute on function
  private.my_shop_ids(), private.is_shop_member(text), private.is_shop_owner(text)
  to authenticated;

-- Server functions ------------------------------------------------------------
-- All security definer with search_path = public; each checks the caller.

-- Creates a shop and makes the caller its owner. profile holds business_profile
-- columns; omitted ones take the column default. Retrying with the same id
-- returns the existing shop to its owner instead of failing.
create function public.create_shop(profile jsonb)
returns public.business_profile
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r public.business_profile;
begin
  if uid is null then
    raise exception 'Not authenticated' using errcode = 'insufficient_privilege';
  end if;

  select * into r from business_profile where id = profile ->> 'id';
  if found then
    if private.is_shop_owner(r.id) then
      return r;
    end if;
    raise exception 'Shop % already exists', r.id using errcode = 'unique_violation';
  end if;

  insert into business_profile (id, name, type)
  values (profile ->> 'id', profile ->> 'name', profile ->> 'type')
  returning * into r;
  -- Overlay the provided keys on the defaulted row.
  r := jsonb_populate_record(r, profile - 'id');
  update business_profile set
    name = r.name,
    type = r.type,
    currency = r.currency,
    tax_label = r.tax_label,
    theme_color = r.theme_color,
    variant_support = r.variant_support,
    expiry_tracking = r.expiry_tracking,
    allow_oversell = r.allow_oversell,
    currency_decimals = r.currency_decimals,
    created_at = r.created_at
  where id = r.id
  returning * into r;

  insert into shop_member (profile_id, user_id, role) values (r.id, uid, 'owner');
  return r;
end;
$$;

-- Records a sale that already happened on a device. In one transaction:
-- inserts the sale and its items, then one 'sale' stock_movement per item
-- (delta -qty, id 'sale:' || sale_item id), which stock_movement_apply applies.
--
-- Idempotent on sale id: a retried upload of a recorded sale changes nothing.
-- Never rejects for stock: stock_movement_apply flags oversells and lines that
-- change no stock in stock_alert. A customer_id or variant_id that no longer
-- exists in the shop (deleted by another device) is stored as null rather than
-- failing the sale.
--
-- sale: sale columns (id and profile_id required). items: array of sale_item
-- columns; sale_id and profile_id are taken from the sale.
create function public.record_sale(sale jsonb, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sale;
  v_sale_id text;
  v_existing_profile text;
  v_alerts integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = 'insufficient_privilege';
  end if;
  if items is null or jsonb_typeof(items) <> 'array' then
    raise exception 'items must be a JSON array' using errcode = 'invalid_parameter_value';
  end if;

  s := jsonb_populate_record(null::public.sale, sale);
  if s.id is null or s.profile_id is null then
    raise exception 'sale.id and sale.profile_id are required'
      using errcode = 'invalid_parameter_value';
  end if;
  if not private.is_shop_member(s.profile_id) then
    raise exception 'Not a member of shop %', s.profile_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Lock the shop row: serialises sales per shop (no deadlocks between
  -- concurrent stock updates). NO KEY UPDATE does not block foreign-key checks
  -- from other writes to the shop's tables.
  perform 1 from business_profile where id = s.profile_id for no key update;

  -- The sale already happened, so a reference another device has since
  -- deleted must not make it fail: drop it, as ON DELETE SET NULL would have.
  if s.customer_id is not null and not exists (
    select 1 from customer c where c.id = s.customer_id and c.profile_id = s.profile_id
  ) then
    s.customer_id := null;
  end if;

  insert into public.sale (
    id, profile_id, customer_id, created_at, subtotal_minor, tax_amount_minor,
    discount_minor, total_minor, payment_method
  ) values (
    s.id, s.profile_id, s.customer_id, coalesce(s.created_at, to_db_time(now())),
    coalesce(s.subtotal_minor, 0), coalesce(s.tax_amount_minor, 0),
    coalesce(s.discount_minor, 0), coalesce(s.total_minor, 0),
    coalesce(s.payment_method, 'cash')
  )
  on conflict (id) do nothing
  returning id into v_sale_id;

  if v_sale_id is null then
    select profile_id into v_existing_profile from public.sale where id = s.id;
    if v_existing_profile is distinct from s.profile_id then
      raise exception 'Sale % belongs to another shop', s.id
        using errcode = 'unique_violation';
    end if;
    return jsonb_build_object('sale_id', s.id, 'duplicate', true, 'stock_alerts', 0);
  end if;

  insert into sale_item (
    id, sale_id, profile_id, product_id, product_name, variant_id, qty,
    unit_price_minor, cost_price_minor
  )
  select i.id, v_sale_id, s.profile_id, i.product_id, i.product_name,
         -- A variant that no longer exists for the product is dropped.
         v.id,
         coalesce(i.qty, 1), coalesce(i.unit_price_minor, 0),
         coalesce(i.cost_price_minor, 0)
  from jsonb_populate_recordset(null::public.sale_item, items) i
  left join product_variant v
    on v.id = i.variant_id and v.product_id = i.product_id and v.profile_id = s.profile_id;

  -- A dropped variant is null here, so its line is flagged by
  -- stock_movement_apply (product with variants) or decrements the product
  -- (now a plain product). A movement the device already uploaded under the
  -- same id is not applied again.
  insert into stock_movement (id, profile_id, product_id, variant_id, delta, reason, sale_id)
  select 'sale:' || si.id, s.profile_id, si.product_id, si.variant_id, -si.qty, 'sale', v_sale_id
  from sale_item si
  where si.sale_id = v_sale_id
  order by si.id
  on conflict (id) do nothing;

  select count(*)::integer into v_alerts from stock_alert where sale_id = v_sale_id;

  return jsonb_build_object('sale_id', v_sale_id, 'duplicate', false, 'stock_alerts', v_alerts);
end;
$$;

-- Owner-only profile update. profile holds id plus the columns to change;
-- omitted columns keep their value, id and created_at never change. A change
-- to currency or currency_decimals fails once the shop has products or sales
-- (business_profile_currency_lock).
create function public.update_profile(profile jsonb)
returns public.business_profile
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.business_profile;
begin
  if not private.is_shop_owner(profile ->> 'id') then
    raise exception 'Only the shop owner can update the profile'
      using errcode = 'insufficient_privilege';
  end if;

  select * into r from business_profile where id = profile ->> 'id' for update;
  r := jsonb_populate_record(r, profile - 'id' - 'created_at');
  update business_profile set
    name = r.name,
    type = r.type,
    currency = r.currency,
    tax_label = r.tax_label,
    theme_color = r.theme_color,
    variant_support = r.variant_support,
    expiry_tracking = r.expiry_tracking,
    allow_oversell = r.allow_oversell,
    currency_decimals = r.currency_decimals
  where id = r.id
  returning * into r;
  return r;
end;
$$;

-- Owner-only. Returns a 10-character single-use code, valid for 7 days, that
-- another signed-in user passes to join_shop.
create function public.create_invite(profile_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  -- 32 symbols without 0/O/1/I, so a byte maps to one symbol uniformly.
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  b bytea;
  v_code text;
  i integer;
begin
  if not private.is_shop_owner(create_invite.profile_id) then
    raise exception 'Only the shop owner can invite'
      using errcode = 'insufficient_privilege';
  end if;

  loop
    -- Random bytes of a v4 UUID, skipping the version and variant bytes.
    b := uuid_send(gen_random_uuid());
    v_code := '';
    foreach i in array array[0, 1, 2, 3, 4, 5, 9, 10, 11, 12] loop
      v_code := v_code || substr(alphabet, get_byte(b, i) % 32 + 1, 1);
    end loop;
    begin
      insert into shop_invite (code, profile_id, created_by, expires_at)
      values (v_code, create_invite.profile_id, auth.uid(),
              to_db_time(now() + interval '7 days'));
      return v_code;
    exception when unique_violation then
      -- Code collision: try another.
    end;
  end loop;
end;
$$;

-- Adds the caller to the invite's shop as staff and uses up the invite.
-- Returns the shop's profile_id. A caller who is already a member gets the
-- profile_id back without using up the invite.
create function public.join_shop(code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  inv public.shop_invite;
begin
  if uid is null then
    raise exception 'Not authenticated' using errcode = 'insufficient_privilege';
  end if;

  select * into inv from shop_invite
  where shop_invite.code = upper(btrim(join_shop.code))
  for update;
  if found and private.is_shop_member(inv.profile_id) then
    return inv.profile_id;
  end if;
  if not found or inv.used_at is not null or inv.expires_at <= to_db_time(now()) then
    raise exception 'Invite code is invalid or expired'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into shop_member (profile_id, user_id, role) values (inv.profile_id, uid, 'staff');
  update shop_invite set used_by = uid, used_at = to_db_time(now())
  where shop_invite.code = inv.code;
  return inv.profile_id;
end;
$$;

revoke all on function
  public.create_shop(jsonb), public.record_sale(jsonb, jsonb),
  public.update_profile(jsonb), public.create_invite(text), public.join_shop(text)
  from public, anon;
grant execute on function
  public.create_shop(jsonb), public.record_sale(jsonb, jsonb),
  public.update_profile(jsonb), public.create_invite(text), public.join_shop(text)
  to authenticated;

-- PowerSync replication -------------------------------------------------------
-- PowerSync streams changes from this publication; shop_invite is not synced.

create publication powersync for table
  public.business_profile, public.shop_member, public.product,
  public.product_variant, public.customer, public.sale, public.sale_item,
  public.expense, public.supplier, public.stock_movement, public.stock_alert,
  public.code_conflict;
