import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'db_time.dart';

/// Central database helper — singleton that owns the SQLite connection.
/// All DAOs receive the [Database] instance from here.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  static const int _version = 1;
  static const String _dbName = 'busybuddy.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // Conventions: money columns end in _minor and hold integer minor units
  // (see core/utils/money.dart); timestamps are UTC ISO-8601 text (see
  // db_time.dart); calendar dates are 'YYYY-MM-DD'.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE business_profile (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('shoes','fashion','grocery','general')),
        currency TEXT NOT NULL DEFAULT 'INR',
        tax_label TEXT NOT NULL DEFAULT 'GST',
        theme_color INTEGER NOT NULL DEFAULT 0xFF6C63FF,
        variant_support INTEGER NOT NULL DEFAULT 0,
        expiry_tracking INTEGER NOT NULL DEFAULT 0,
        -- 1: a sale may take stock below 0. 0: SaleDao.recordSale rejects it.
        allow_oversell INTEGER NOT NULL DEFAULT 0 CHECK (allow_oversell IN (0, 1)),
        -- Fixed once the profile has products or sales: amounts are stored in
        -- minor units, so changing it would rescale every stored amount.
        currency_decimals INTEGER NOT NULL DEFAULT 2 CHECK (currency_decimals BETWEEN 0 AND 3),
        google_account_id TEXT,
        created_at TEXT NOT NULL DEFAULT $sqlNow
      )
    ''');

    await db.execute('''
      CREATE TABLE product (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sku TEXT,
        barcode TEXT,
        price_minor INTEGER NOT NULL DEFAULT 0 CHECK (price_minor >= 0),
        cost_price_minor INTEGER NOT NULL DEFAULT 0 CHECK (cost_price_minor >= 0),
        category TEXT,
        -- For a product with variants this is the sum of the variants' stock,
        -- kept in step by ProductDao.saveWithVariants and SaleDao.recordSale.
        -- No CHECK >= 0: it goes negative when the profile allows oversells.
        stock_qty INTEGER NOT NULL DEFAULT 0,
        low_stock_threshold INTEGER NOT NULL DEFAULT 5 CHECK (low_stock_threshold >= 0),
        expiry_date TEXT,
        image_path TEXT,
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        created_at TEXT NOT NULL DEFAULT $sqlNow,
        updated_at TEXT NOT NULL DEFAULT $sqlNow,
        FOREIGN KEY (profile_id) REFERENCES business_profile(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE product_variant (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        size TEXT,
        color TEXT,
        stock_qty INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT $sqlNow,
        FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE customer (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        created_at TEXT NOT NULL DEFAULT $sqlNow,
        FOREIGN KEY (profile_id) REFERENCES business_profile(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE sale (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL,
        customer_id TEXT,
        created_at TEXT NOT NULL DEFAULT $sqlNow,
        subtotal_minor INTEGER NOT NULL DEFAULT 0 CHECK (subtotal_minor >= 0),
        tax_amount_minor INTEGER NOT NULL DEFAULT 0 CHECK (tax_amount_minor >= 0),
        discount_minor INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
        total_minor INTEGER NOT NULL DEFAULT 0 CHECK (total_minor >= 0),
        payment_method TEXT NOT NULL DEFAULT 'cash',
        FOREIGN KEY (profile_id) REFERENCES business_profile(id) ON DELETE CASCADE,
        FOREIGN KEY (customer_id) REFERENCES customer(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_item (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        variant_id TEXT,
        qty INTEGER NOT NULL DEFAULT 1 CHECK (qty > 0),
        unit_price_minor INTEGER NOT NULL DEFAULT 0 CHECK (unit_price_minor >= 0),
        -- Cost at time of sale, so profit stays right after cost edits.
        cost_price_minor INTEGER NOT NULL DEFAULT 0 CHECK (cost_price_minor >= 0),
        FOREIGN KEY (sale_id) REFERENCES sale(id) ON DELETE CASCADE,
        -- No ON DELETE action: a product that appears in a sale cannot be
        -- deleted (archive it instead). NO ACTION rather than RESTRICT so a
        -- profile delete, which cascades to both sale and product, still works.
        FOREIGN KEY (product_id) REFERENCES product(id),
        FOREIGN KEY (variant_id) REFERENCES product_variant(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE expense (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL,
        amount_minor INTEGER NOT NULL DEFAULT 0 CHECK (amount_minor >= 0),
        category TEXT,
        note TEXT,
        date TEXT NOT NULL DEFAULT (date('now', 'localtime')),
        created_at TEXT NOT NULL DEFAULT $sqlNow,
        FOREIGN KEY (profile_id) REFERENCES business_profile(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE supplier (
        id TEXT PRIMARY KEY,
        profile_id TEXT NOT NULL,
        name TEXT NOT NULL,
        contact TEXT,
        email TEXT,
        created_at TEXT NOT NULL DEFAULT $sqlNow,
        FOREIGN KEY (profile_id) REFERENCES business_profile(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE backup_log (
        id TEXT PRIMARY KEY,
        last_backup_at TEXT NOT NULL,
        drive_file_id TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        google_account_id TEXT,
        created_at TEXT NOT NULL DEFAULT $sqlNow
      )
    ''');

    // Indexes for common queries
    await db.execute('CREATE INDEX idx_product_profile ON product(profile_id)');
    await db.execute('CREATE INDEX idx_product_category ON product(category)');
    await db.execute('CREATE INDEX idx_product_variant_product ON product_variant(product_id)');
    await db.execute('CREATE INDEX idx_customer_profile ON customer(profile_id)');
    await db.execute('CREATE INDEX idx_sale_profile ON sale(profile_id)');
    await db.execute('CREATE INDEX idx_sale_created ON sale(created_at)');
    await db.execute('CREATE INDEX idx_sale_customer ON sale(customer_id)');
    await db.execute('CREATE INDEX idx_sale_item_sale ON sale_item(sale_id)');
    await db.execute('CREATE INDEX idx_expense_profile ON expense(profile_id)');
    await db.execute('CREATE INDEX idx_supplier_profile ON supplier(profile_id)');

    // SKU and barcode are unique per profile among active products; archiving
    // a product frees its codes for reuse.
    await db.execute('CREATE UNIQUE INDEX idx_product_sku ON product(profile_id, sku) '
        'WHERE sku IS NOT NULL AND archived = 0');
    await db.execute('CREATE UNIQUE INDEX idx_product_barcode ON product(profile_id, barcode) '
        'WHERE barcode IS NOT NULL AND archived = 0');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migration logic goes here
  }

  /// Check whether the database file exists (used to detect first-launch).
  Future<bool> databaseExists() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return databaseFactory.databaseExists(path);
  }

  /// Wipe database — used when user chooses "start fresh".
  Future<void> deleteDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    await deleteDatabase(path);
    _database = null;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
