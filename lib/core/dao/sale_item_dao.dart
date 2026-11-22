import '../db/base_dao.dart';
import '../db/database_helper.dart';
import '../models/sale_item.dart';

class SaleItemDao extends BaseDao<SaleItem> {
  @override
  String get tableName => 'sale_item';

  @override
  Map<String, dynamic> toMap(SaleItem item) => item.toMap();

  @override
  SaleItem fromMap(Map<String, dynamic> map) => SaleItem.fromMap(map);

  Future<List<SaleItem>> getBySale(String saleId) async {
    return query(where: 'sale_id = ?', whereArgs: [saleId]);
  }

  /// Average actual selling price per product (product id -> minor units),
  /// weighted by quantity and rounded to the nearest minor unit. Uses line
  /// prices before any sale-level discount. Products never sold are absent.
  Future<Map<String, int>> getAvgSellingPricesMinor(String profileId) async {
    final db = await DatabaseHelper().database;
    final rows = await db.rawQuery(
      'SELECT si.product_id, '
      'CAST(ROUND(1.0 * SUM(si.qty * si.unit_price_minor) / SUM(si.qty)) AS INTEGER) AS avg_minor '
      'FROM sale_item si JOIN sale s ON s.id = si.sale_id '
      'WHERE s.profile_id = ? GROUP BY si.product_id',
      [profileId],
    );
    return {for (final r in rows) r['product_id'] as String: r['avg_minor'] as int};
  }
}
