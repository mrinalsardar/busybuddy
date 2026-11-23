import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;
import '../db/base_dao.dart';
import '../models/product_variant.dart';
import '../models/stock_movement.dart';
import 'stock_movement_dao.dart';

class ProductVariantDao extends BaseDao<ProductVariant> {
  @override
  String get tableName => 'product_variant';

  @override
  Map<String, dynamic> toMap(ProductVariant item) => item.toMap();

  @override
  ProductVariant fromMap(Map<String, dynamic> map) => ProductVariant.fromMap(map);

  /// Inserts a variant at stock 0 plus an `initial` stock movement of its
  /// stockQty; the product's stock becomes the variant total.
  @override
  Future<int> insert(ProductVariant item) async {
    await (await db).writeTransaction((tx) async {
      await insertRow(tx, tableName, {...item.toMap(), 'stock_qty': 0});
      await syncVariantStockTotal(tx, item.productId);
      if (item.stockQty != 0) {
        await recordStockMovement(tx,
            profileId: item.profileId,
            productId: item.productId,
            variantId: item.id,
            delta: item.stockQty,
            reason: StockMovementReason.initial);
      }
    });
    return 1;
  }

  /// Saves a variant's fields; a changed stockQty becomes a `correction`
  /// stock movement of the difference.
  @override
  Future<int> update(ProductVariant item, String id) async {
    return (await db).writeTransaction((tx) async {
      final row = await tx.getOptional('SELECT stock_qty FROM product_variant WHERE id = ?', [id]);
      if (row == null) return 0;
      await updateRow(tx, tableName, id, item.toMap()..remove('stock_qty'));
      final delta = item.stockQty - (row['stock_qty'] as int);
      if (delta != 0) {
        await recordStockMovement(tx,
            profileId: item.profileId,
            productId: item.productId,
            variantId: id,
            delta: delta,
            reason: StockMovementReason.correction);
      }
      return 1;
    });
  }

  /// Deletes a variant; sale items keep their line with no variant.
  @override
  Future<int> delete(String id) async {
    return (await db).writeTransaction((tx) => deleteVariantRow(tx, id));
  }

  Future<List<ProductVariant>> getByProduct(String productId) async {
    return query(where: 'product_id = ?', whereArgs: [productId]);
  }

  Future<void> deleteByProduct(String productId) async {
    final variants = await query(where: 'product_id = ?', whereArgs: [productId]);
    for (final v in variants) {
      await delete(v.id);
    }
  }
}

/// Deletes a variant the way the server's foreign keys do: sale items that
/// name it get variant_id null, and the product's stock becomes the total of
/// its remaining variants (0 if none are left).
Future<int> deleteVariantRow(SqliteWriteContext tx, String id) async {
  final row = await tx.getOptional('SELECT product_id FROM product_variant WHERE id = ?', [id]);
  if (row == null) return 0;
  await tx.execute('UPDATE sale_item SET variant_id = NULL WHERE variant_id = ?', [id]);
  await tx.execute('DELETE FROM product_variant WHERE id = ?', [id]);
  await syncVariantStockTotal(tx, row['product_id'] as String);
  return 1;
}
