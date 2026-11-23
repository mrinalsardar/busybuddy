import '../db/base_dao.dart';
import '../db/db_time.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import 'sale_item_dao.dart';
import 'stock_movement_dao.dart';

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

  @override
  void validate(Sale item) {
    check(item.subtotalMinor >= 0 &&
            item.taxAmountMinor >= 0 &&
            item.discountMinor >= 0 &&
            item.totalMinor >= 0,
        'Sale amounts cannot be negative');
  }

  /// Deletes a sale and its line items.
  @override
  Future<int> delete(String id) async {
    return (await db).writeTransaction((tx) async {
      await tx.execute('DELETE FROM sale_item WHERE sale_id = ?', [id]);
      return deleteRow(tx, tableName, id);
    });
  }

  /// Record a sale + its line items and decrement stock in a single local
  /// transaction. Throws [SaleRejectedException] (and writes nothing) if any
  /// line names a variant product without a variant, or would oversell while
  /// the profile's `allow_oversell` is off. With it on, stock goes negative.
  ///
  /// The stock change is local only, for display: the sale uploads as one
  /// `record_sale` call (see SupabaseConnector), and the server writes the
  /// sale's stock movements itself.
  Future<void> recordSale(Sale sale, List<SaleItem> items) async {
    validate(sale);
    final itemDao = SaleItemDao();
    for (final item in items) {
      itemDao.validate(item);
    }
    final db = await this.db;
    await db.writeTransaction((tx) async {
      final profile = await tx.getOptional(
          'SELECT allow_oversell FROM business_profile WHERE id = ?', [sale.profileId]);
      final allowOversell = profile?['allow_oversell'] == 1;

      await insertRow(tx, 'sale', sale.toMap());
      for (final item in items) {
        await insertRow(tx, 'sale_item',
            item.copyWith(saleId: sale.id, profileId: sale.profileId).toMap());

        // Product stock is the variant total for variant products, so both
        // change in that case.
        final String table;
        final String rowId;
        if (item.variantId == null) {
          if (await hasVariants(tx, item.productId)) {
            throw SaleRejectedException('Pick a size/colour for ${item.productName}');
          }
          (table, rowId) = ('product', item.productId);
        } else {
          (table, rowId) = ('product_variant', item.variantId!);
        }
        final row = await tx.getOptional(
          'SELECT stock_qty FROM $table WHERE id = ?${table == 'product_variant' ? ' AND product_id = ?' : ''}',
          [rowId, if (table == 'product_variant') item.productId],
        );
        if (row == null || (!allowOversell && (row['stock_qty'] as int) < item.qty)) {
          throw SaleRejectedException('Not enough stock for ${item.productName}');
        }
        await tx.execute('UPDATE $table SET stock_qty = stock_qty - ? WHERE id = ?', [item.qty, rowId]);
        if (item.variantId != null) await syncVariantStockTotal(tx, item.productId);
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
    final db = await this.db;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + 1);
    final result = await db.get(
      'SELECT COALESCE(SUM(total_minor), 0) AS day_total FROM sale '
      'WHERE profile_id = ? AND created_at >= ? AND created_at < ?',
      [profileId, toDbTime(start), toDbTime(end)],
    );
    return result['day_total'] as int;
  }
}
