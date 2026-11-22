import '../db/base_dao.dart';
import '../db/database_helper.dart';
import '../db/db_time.dart';
import '../models/product.dart';
import '../models/product_variant.dart';

class ProductDao extends BaseDao<Product> {
  @override
  String get tableName => 'product';

  @override
  Map<String, dynamic> toMap(Product item) => item.toMap();

  @override
  Product fromMap(Map<String, dynamic> map) => Product.fromMap(map);

  Future<List<Product>> getByProfile(String profileId, {String? category, String? searchQuery}) async {
    var where = 'profile_id = ? AND archived = 0';
    final args = <dynamic>[profileId];
    if (category != null && category.isNotEmpty) {
      where += ' AND category = ?';
      args.add(category);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      where += ' AND (name LIKE ? OR sku LIKE ? OR barcode LIKE ?)';
      final q = '%$searchQuery%';
      args.addAll([q, q, q]);
    }
    return query(where: where, whereArgs: args, orderBy: 'name ASC');
  }

  Future<List<Product>> getLowStock(String profileId) async {
    return query(
      where: 'profile_id = ? AND archived = 0 AND stock_qty <= low_stock_threshold',
      whereArgs: [profileId],
      orderBy: 'stock_qty ASC',
    );
  }

  Future<List<String>> getCategories(String profileId) async {
    final db = await (super.query(where: 'profile_id = ? AND archived = 0 AND category IS NOT NULL',
        whereArgs: [profileId]));
    return db.map((p) => p.category!).toSet().toList()..sort();
  }

  Future<void> updateStock(String productId, int newQty) async {
    final db = await (super.getById(productId));
    if (db != null) {
      await update(db.copyWith(stockQty: newQty, updatedAt: DateTime.now()), productId);
    }
  }

  /// Hides a product from inventory and POS. Products are never hard-deleted
  /// from the UI because sale_item rows reference them.
  Future<void> archive(String productId) async {
    final db = await DatabaseHelper().database;
    await db.update(
      tableName,
      {'archived': 1, 'updated_at': toDbTime(DateTime.now())},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  /// Saves a product and (when [variants] is non-null) replaces its variant
  /// set, all in one transaction. Variants missing from [variants] are deleted;
  /// existing ones are updated in place (never REPLACEd, which would fire
  /// ON DELETE SET NULL on sale_item.variant_id).
  ///
  /// A product with variants gets stock_qty = sum of its variants' stock.
  Future<void> saveWithVariants(
    Product product, {
    required bool isNew,
    List<ProductVariant>? variants,
  }) async {
    final stored = (variants != null && variants.isNotEmpty)
        ? product.copyWith(stockQty: variants.fold<int>(0, (sum, v) => sum + v.stockQty))
        : product;
    final db = await DatabaseHelper().database;
    await db.transaction((txn) async {
      if (isNew) {
        await txn.insert(tableName, stored.toMap());
      } else {
        await txn.update(tableName, stored.toMap(),
            where: 'id = ?', whereArgs: [product.id]);
      }
      if (variants == null) return;

      final keepIds = variants.map((v) => v.id).toList();
      await txn.delete(
        'product_variant',
        where: keepIds.isEmpty
            ? 'product_id = ?'
            : 'product_id = ? AND id NOT IN (${List.filled(keepIds.length, '?').join(', ')})',
        whereArgs: [product.id, ...keepIds],
      );
      for (final v in variants) {
        final updated = await txn.update('product_variant', v.toMap(),
            where: 'id = ?', whereArgs: [v.id]);
        if (updated == 0) await txn.insert('product_variant', v.toMap());
      }
    });
  }
}
