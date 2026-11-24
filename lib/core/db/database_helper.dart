import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'schema.dart';

/// Central database helper — singleton that owns the PowerSync database, the
/// device's local SQLite copy of the shop data. All DAOs get the
/// [PowerSyncDatabase] from here.
///
/// The app works fully on the local copy. Once a Supabase session exists,
/// [connect] starts syncing it with the server; local writes queue until then.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static const String _dbName = 'busybuddy.db';

  static Future<PowerSyncDatabase>? _database;
  static String? _path;

  /// The database, opened on first use at the path given to [open] or, by
  /// default, in the app support directory.
  Future<PowerSyncDatabase> get database => _database ??= _open();

  /// Opens the database at [path] (tests pass a temporary file). Has no
  /// effect if it is already open.
  Future<PowerSyncDatabase> open({String? path}) {
    if (_database == null) _path = path;
    return database;
  }

  Future<String> _dbPath() async => _path ?? join((await getApplicationSupportDirectory()).path, _dbName);

  /// Directory of the product image files, next to the database so that they
  /// are cleared with it. The OS never purges it (a picture added offline may
  /// exist nowhere else yet).
  Future<Directory> productImageDir() async => Directory(join(dirname(await _dbPath()), 'product_images'));

  Future<PowerSyncDatabase> _open() async {
    final path = await _dbPath();
    final db = PowerSyncDatabase(schema: schema, path: path);
    try {
      await db.initialize();
    } catch (_) {
      _database = null;
      rethrow;
    }
    return db;
  }

  /// Starts syncing with the server through [connector]. Call once per
  /// signed-in session.
  Future<void> connect(PowerSyncBackendConnector connector) async {
    await (await database).connect(connector: connector);
  }

  /// Stops syncing; local data and queued uploads are kept.
  Future<void> disconnect() async {
    await (await database).disconnect();
  }

  /// Stops syncing and deletes all local data, including local-only tables,
  /// changes not yet uploaded and the product image files.
  Future<void> disconnectAndClear() async {
    await (await database).disconnectAndClear();
    final images = await productImageDir();
    if (await images.exists()) await images.delete(recursive: true);
  }

  /// Wipe local data — used when user chooses "start fresh". Data already on
  /// the server is not touched.
  Future<void> deleteDb() => disconnectAndClear();

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null) await (await db).close();
  }
}
