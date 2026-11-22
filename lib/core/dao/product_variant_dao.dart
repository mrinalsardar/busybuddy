import '../db/base_dao.dart';
import '../models/product_variant.dart';

class ProductVariantDao extends BaseDao<ProductVariant> {
  @override
  String get tableName => 'product_variant';

  @override
  Map<String, dynamic> toMap(ProductVariant item) => item.toMap();

  @override
  ProductVariant fromMap(Map<String, dynamic> map) => ProductVariant.fromMap(map);

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
