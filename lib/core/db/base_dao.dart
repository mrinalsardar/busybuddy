import 'package:flutter/foundation.dart' show protected;
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart' show SqliteReadContext, SqliteWriteContext;
import 'data_exceptions.dart';
import 'database_helper.dart';

/// Base DAO providing common CRUD operations for any table.
///
/// Every write goes into PowerSync's upload queue, so it reaches the server
/// once the device is connected (see SupabaseConnector).
abstract class BaseDao<T> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Name of the table this DAO manages.
  String get tableName;

  /// Convert a domain model to a Map for DB insertion.
  Map<String, dynamic> toMap(T item);

  /// Convert a DB row Map to a domain model.
  T fromMap(Map<String, dynamic> map);

  /// Throws [DataValidationException] if [item] breaks a schema rule. The
  /// local tables have no CHECK constraints, so subclasses check them here;
  /// [insert] and [update] call it before writing.
  void validate(T item) {}

  @protected
  Future<PowerSyncDatabase> get db => _dbHelper.database;

  /// Inserts a new row. Throws [DuplicateIdException] if the id already
  /// exists; use [update] for existing rows.
  Future<int> insert(T item) async {
    validate(item);
    await (await db).writeTransaction((tx) => insertRow(tx, tableName, toMap(item)));
    return 1;
  }

  /// Updates the row with [id]. Returns the number of rows changed (0 or 1).
  Future<int> update(T item, String id) async {
    validate(item);
    return (await db).writeTransaction((tx) => updateRow(tx, tableName, id, toMap(item)));
  }

  /// Deletes the row with [id]. Returns the number of rows deleted (0 or 1).
  Future<int> delete(String id) async {
    return (await db).writeTransaction((tx) => deleteRow(tx, tableName, id));
  }

  Future<T?> getById(String id) async {
    final row = await (await db).getOptional('SELECT * FROM $tableName WHERE id = ?', [id]);
    return row == null ? null : fromMap(row);
  }

  Future<List<T>> getAll() async {
    final rows = await (await db).getAll('SELECT * FROM $tableName');
    return rows.map((m) => fromMap(m)).toList();
  }

  Future<List<T>> query({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final sql = StringBuffer('SELECT * FROM $tableName');
    if (where != null) sql.write(' WHERE $where');
    if (orderBy != null) sql.write(' ORDER BY $orderBy');
    if (limit != null) sql.write(' LIMIT $limit');
    if (offset != null) sql.write('${limit == null ? ' LIMIT -1' : ''} OFFSET $offset');
    final rows = await (await db).getAll(sql.toString(), whereArgs ?? const []);
    return rows.map((m) => fromMap(m)).toList();
  }

  Future<int> count({String? where, List<Object?>? whereArgs}) async {
    final row = await (await db).get(
      'SELECT COUNT(*) AS cnt FROM $tableName${where != null ? ' WHERE $where' : ''}',
      whereArgs ?? const [],
    );
    return row['cnt'] as int;
  }
}

/// Whether [table] has a row with [id].
Future<bool> rowExists(SqliteReadContext ctx, String table, String id) async =>
    await ctx.getOptional('SELECT 1 FROM $table WHERE id = ?', [id]) != null;

/// Inserts [row] into [table]. Throws [DuplicateIdException] if its id exists.
Future<void> insertRow(SqliteWriteContext tx, String table, Map<String, Object?> row) async {
  if (await rowExists(tx, table, row['id'] as String)) {
    throw DuplicateIdException(table, row['id']);
  }
  final cols = row.keys.toList();
  await tx.execute(
    'INSERT INTO $table (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})',
    [for (final c in cols) row[c]],
  );
}

/// Sets [values] (any `id` key is ignored) on the row of [table] with [id].
/// Returns 1, or 0 if there is no such row.
Future<int> updateRow(SqliteWriteContext tx, String table, String id, Map<String, Object?> values) async {
  final cols = values.keys.where((c) => c != 'id').toList();
  if (!await rowExists(tx, table, id)) return 0;
  if (cols.isEmpty) return 1;
  await tx.execute(
    'UPDATE $table SET ${cols.map((c) => '$c = ?').join(', ')} WHERE id = ?',
    [for (final c in cols) values[c], id],
  );
  return 1;
}

/// Deletes the row of [table] with [id]. Returns 1, or 0 if there is none.
Future<int> deleteRow(SqliteWriteContext tx, String table, String id) async {
  if (!await rowExists(tx, table, id)) return 0;
  await tx.execute('DELETE FROM $table WHERE id = ?', [id]);
  return 1;
}

/// Throws [DataValidationException] with [message] unless [ok].
void check(bool ok, String message) {
  if (!ok) throw DataValidationException(message);
}
