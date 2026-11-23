import 'package:powersync/powersync.dart';

/// Client schema of the PowerSync database: the tables synced from Supabase
/// (see supabase/migrations and powersync/sync-rules.yaml), plus local-only
/// tables. Columns only: PowerSync adds the text `id` column itself, and its
/// tables are views without constraints, defaults or foreign keys, so the DAOs
/// enforce those rules (see data_exceptions.dart).
///
/// Conventions: money columns end in _minor and hold integer minor units
/// (see core/utils/money.dart); timestamps are UTC ISO-8601 text (see
/// db_time.dart); calendar dates are 'YYYY-MM-DD'; flags are integers 0/1.
///
/// `ignoreEmptyUpdates` keeps an UPDATE that changes nothing out of the upload
/// queue.
const schema = Schema([
  Table(
    'business_profile',
    [
      Column.text('name'),
      // shoes | fashion | grocery | general
      Column.text('type'),
      Column.text('currency'),
      Column.text('tax_label'),
      Column.integer('theme_color'),
      Column.integer('variant_support'),
      Column.integer('expiry_tracking'),
      // 1: a sale may take stock below 0. 0: SaleDao.recordSale rejects it.
      Column.integer('allow_oversell'),
      // Fixed once the profile has products or sales: amounts are stored in
      // minor units, so changing it would rescale every stored amount.
      Column.integer('currency_decimals'),
      // Local only: not on the server, and never uploaded.
      Column.text('google_account_id'),
      Column.text('created_at'),
    ],
    ignoreEmptyUpdates: true,
  ),
  // Synced read-only; written by the server functions. id is
  // profile_id || ':' || user_id.
  Table('shop_member', [
    Column.text('profile_id'),
    Column.text('user_id'),
    // owner | staff
    Column.text('role'),
    Column.text('created_at'),
  ]),
  Table(
    'product',
    [
      Column.text('profile_id'),
      Column.text('name'),
      Column.text('sku'),
      Column.text('barcode'),
      Column.integer('price_minor'),
      Column.integer('cost_price_minor'),
      Column.text('category'),
      // Changed only through stock_movement rows; never uploaded. For a
      // product with variants it is the sum of the variants' stock. Goes
      // negative when the profile allows oversells.
      Column.integer('stock_qty'),
      Column.integer('low_stock_threshold'),
      Column.text('expiry_date'),
      Column.text('image_path'),
      Column.integer('archived'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      Index('profile', [IndexedColumn('profile_id')]),
      Index('category', [IndexedColumn('category')]),
    ],
    ignoreEmptyUpdates: true,
  ),
  Table(
    'product_variant',
    [
      Column.text('product_id'),
      Column.text('profile_id'),
      Column.text('size'),
      Column.text('color'),
      // Like product.stock_qty: changed only through stock_movement rows.
      Column.integer('stock_qty'),
      Column.text('created_at'),
    ],
    indexes: [
      Index('product', [IndexedColumn('product_id')]),
    ],
    ignoreEmptyUpdates: true,
  ),
  Table(
    'customer',
    [
      Column.text('profile_id'),
      Column.text('name'),
      Column.text('phone'),
      Column.text('email'),
      Column.text('created_at'),
    ],
    indexes: [
      Index('profile', [IndexedColumn('profile_id')]),
    ],
    ignoreEmptyUpdates: true,
  ),
  Table(
    'sale',
    [
      Column.text('profile_id'),
      Column.text('customer_id'),
      Column.text('created_at'),
      Column.integer('subtotal_minor'),
      Column.integer('tax_amount_minor'),
      Column.integer('discount_minor'),
      Column.integer('total_minor'),
      Column.text('payment_method'),
    ],
    indexes: [
      Index('profile', [IndexedColumn('profile_id')]),
      Index('created', [IndexedColumn('created_at')]),
      Index('customer', [IndexedColumn('customer_id')]),
    ],
    ignoreEmptyUpdates: true,
  ),
  Table(
    'sale_item',
    [
      Column.text('sale_id'),
      Column.text('profile_id'),
      Column.text('product_id'),
      Column.text('product_name'),
      Column.text('variant_id'),
      Column.integer('qty'),
      Column.integer('unit_price_minor'),
      // Cost at time of sale, so profit stays right after cost edits.
      Column.integer('cost_price_minor'),
    ],
    indexes: [
      Index('sale', [IndexedColumn('sale_id')]),
      Index('product', [IndexedColumn('product_id')]),
    ],
    ignoreEmptyUpdates: true,
  ),
  Table(
    'expense',
    [
      Column.text('profile_id'),
      Column.integer('amount_minor'),
      Column.text('category'),
      Column.text('note'),
      Column.text('date'),
      Column.text('created_at'),
    ],
    indexes: [
      Index('profile', [IndexedColumn('profile_id')]),
    ],
    ignoreEmptyUpdates: true,
  ),
  Table(
    'supplier',
    [
      Column.text('profile_id'),
      Column.text('name'),
      Column.text('contact'),
      Column.text('email'),
      Column.text('created_at'),
    ],
    indexes: [
      Index('profile', [IndexedColumn('profile_id')]),
    ],
    ignoreEmptyUpdates: true,
  ),
  // Append-only stock ledger (see StockMovementDao). Sale movements are
  // written by the server's record_sale and only synced down.
  Table(
    'stock_movement',
    [
      Column.text('profile_id'),
      Column.text('product_id'),
      Column.text('variant_id'),
      Column.integer('delta'),
      // initial | restock | correction | sale | conversion
      Column.text('reason'),
      Column.text('sale_id'),
      Column.text('created_by'),
      Column.text('created_at'),
    ],
    indexes: [
      Index('product', [IndexedColumn('product_id')]),
    ],
  ),
  // Written by the server: oversells and movements that changed no stock.
  Table('stock_alert', [
    Column.text('profile_id'),
    Column.text('product_id'),
    Column.text('variant_id'),
    Column.text('movement_id'),
    Column.text('sale_id'),
    Column.integer('stock_after'),
    Column.text('created_at'),
  ]),
  // Written by the server: two active products of a shop with the same SKU
  // or barcode.
  Table('code_conflict', [
    Column.text('profile_id'),
    Column.text('product_id'),
    Column.text('other_product_id'),
    // sku | barcode
    Column.text('field'),
    Column.text('value'),
    Column.text('created_at'),
    Column.text('resolved_at'),
  ]),
  // Local only: the planned Drive backup is not part of the server.
  Table.localOnly('backup_log', [
    Column.text('last_backup_at'),
    Column.text('drive_file_id'),
    Column.text('status'),
    Column.text('google_account_id'),
    Column.text('created_at'),
  ]),
  // Local only: uploads the server rejected permanently (see
  // SupabaseConnector). They are skipped so later changes still upload.
  Table.localOnly('upload_error', [
    Column.text('table_name'),
    // PUT | PATCH | DELETE
    Column.text('op'),
    Column.text('row_id'),
    // JSON of the change.
    Column.text('data'),
    // SQLSTATE or PostgREST code, when there is one.
    Column.text('code'),
    Column.text('message'),
    Column.text('created_at'),
  ]),
]);
