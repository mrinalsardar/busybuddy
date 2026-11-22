import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// Base DAO providing common CRUD operations for any table.
abstract class BaseDao<T> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Name of the SQLite table this DAO manages.
  String get tableName;

  /// Convert a domain model to a Map for DB insertion.
  Map<String, dynamic> toMap(T item);

  /// Convert a DB row Map to a domain model.
  T fromMap(Map<String, dynamic> map);

  Future<Database> get _db => _dbHelper.database;

  /// Inserts a new row. Throws if the id already exists.
  ///
  /// Deliberately not ConflictAlgorithm.replace: SQLite implements REPLACE as
  /// delete + insert, and the delete fires ON DELETE CASCADE / SET NULL on
  /// every child table. Use [update] for existing rows.
  Future<int> insert(T item) async {
    final db = await _db;
    return db.insert(tableName, toMap(item));
  }

  Future<int> update(T item, String id) async {
    final db = await _db;
    return db.update(
      tableName,
      toMap(item),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(String id) async {
    final db = await _db;
    return db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<T?> getById(String id) async {
    final db = await _db;
    final maps = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  Future<List<T>> getAll() async {
    final db = await _db;
    final maps = await db.query(tableName);
    return maps.map((m) => fromMap(m)).toList();
  }

  Future<List<T>> query({
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await _db;
    final maps = await db.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => fromMap(m)).toList();
  }

  Future<int> count({String? where, List<dynamic>? whereArgs}) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $tableName${where != null ? ' WHERE $where' : ''}',
      whereArgs,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
