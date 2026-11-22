import 'package:sqflite/sqflite.dart';
import '../db/base_dao.dart';
import '../db/database_helper.dart';
import '../db/db_time.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';

/// Thrown by [SaleDao.recordSale] when a line can't be sold: not enough stock
/// (and the profile doesn't allow oversells), or a product with variants sold
/// without picking one. Nothing is written.
class SaleRejectedException implements Exception {
  final String message;
  const SaleRejectedException(this.message);

  @override
  String toString() => message;
}

class SaleDao extends BaseDao<Sale> {
  @override
  String get tableName => 'sale';

  @override
  Map<String, dynamic> toMap(Sale item) => item.toMap();

  @override
  Sale fromMap(Map<String, dynamic> map) => Sale.fromMap(map);

  /// Record a sale + its line items and decrement stock in a single
  /// transaction. Throws [SaleRejectedException] (and writes nothing) if any
  /// line names a variant product without a variant, or would oversell while
  /// the profile's `allow_oversell` is off. With it on, stock goes negative.
  Future<void> recordSale(Sale sale, List<SaleItem> items) async {
    final db = await DatabaseHelper().database;
    await db.transaction((txn) async {
      final allowOversell = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT allow_oversell FROM business_profile WHERE id = ?',
              [sale.profileId])) ==
          1;
      // Without the stock clause the UPDATE always matches (unless the row is
      // missing), so stock can go negative.
      final stockClause = allowOversell ? '' : ' AND stock_qty >= ?';
      List<Object?> stockArg(SaleItem item) => allowOversell ? [] : [item.qty];

      await txn.insert('sale', sale.toMap());
      final now = toDbTime(DateTime.now());
      for (final item in items) {
        await txn.insert('sale_item', item.toMap());

        if (item.variantId == null) {
          final variantCount = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM product_variant WHERE product_id = ?',
              [item.productId]))!;
          if (variantCount > 0) {
            throw SaleRejectedException('Pick a size/colour for ${item.productName}');
          }
        } else {
          final updated = await txn.rawUpdate(
            'UPDATE product_variant SET stock_qty = stock_qty - ? '
            'WHERE id = ? AND product_id = ?$stockClause',
            [item.qty, item.variantId, item.productId, ...stockArg(item)],
          );
          if (updated == 0) {
            throw SaleRejectedException('Not enough stock for ${item.productName}');
          }
        }

        // Product stock is the variant total for variant products, so it is
        // decremented in both cases.
        final updated = await txn.rawUpdate(
          'UPDATE product SET stock_qty = stock_qty - ?, updated_at = ? '
          'WHERE id = ?$stockClause',
          [item.qty, now, item.productId, ...stockArg(item)],
        );
        if (updated == 0) {
          throw SaleRejectedException('Not enough stock for ${item.productName}');
        }
      }
    });
  }

  Future<List<Sale>> getByProfile(String profileId, {int? limit}) async {
    return query(
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Total of today's sales (local calendar day), in minor units.
  Future<int> getTodayTotalMinor(String profileId) async {
    final db = await DatabaseHelper().database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + 1);
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(total_minor), 0) AS day_total FROM sale '
      'WHERE profile_id = ? AND created_at >= ? AND created_at < ?',
      [profileId, toDbTime(start), toDbTime(end)],
    );
    return result.first['day_total'] as int;
  }
}
