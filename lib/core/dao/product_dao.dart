import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;
import '../db/base_dao.dart';
import '../db/data_exceptions.dart';
import '../db/db_time.dart';
import '../db/image_queue.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/stock_movement.dart';
import 'product_variant_dao.dart';
import 'stock_movement_dao.dart';

class ProductDao extends BaseDao<Product> {
  @override
  String get tableName => 'product';

  @override
  Map<String, dynamic> toMap(Product item) => item.toMap();

  @override
  Product fromMap(Map<String, dynamic> map) => Product.fromMap(map);

  @override
  void validate(Product item) {
    check(item.priceMinor >= 0, 'Price cannot be negative');
    check(item.costPriceMinor >= 0, 'Cost price cannot be negative');
    check(item.lowStockThreshold >= 0, 'Low stock threshold cannot be negative');
  }

  /// Inserts a new product; its stockQty becomes an `initial` stock movement.
  /// See [saveWithVariants].
  @override
  Future<int> insert(Product item) async {
    await saveWithVariants(item, isNew: true);
    return 1;
  }

  /// Saves a product's fields; a changed stockQty becomes a `correction`
  /// stock movement. See [saveWithVariants].
  @override
  Future<int> update(Product item, String id) async {
    if (await getById(id) == null) return 0;
    await saveWithVariants(item.copyWith(id: id), isNew: false);
    return 1;
  }

  /// Deletes a product and its variants. Throws [RecordInUseException] if a
  /// sale references it: archive it instead.
  @override
  Future<int> delete(String id) async {
    return (await db).writeTransaction((tx) async {
      if (await tx.getOptional('SELECT 1 FROM sale_item WHERE product_id = ?', [id]) != null) {
        throw const RecordInUseException('A product used in a sale cannot be deleted; archive it');
      }
      final imagePath = (await tx.getOptional('SELECT image_path FROM product WHERE id = ?', [id]))?['image_path'];
      await tx.execute('DELETE FROM product_variant WHERE product_id = ?', [id]);
      final deleted = await deleteRow(tx, tableName, id);
      if (imagePath is String) await queueImageDelete(tx, imagePath);
      return deleted;
    });
  }

  Future<List<Product>> getByProfile(String profileId, {String? category, String? searchQuery}) async {
    var where = 'profile_id = ? AND archived = 0';
    final args = <Object?>[profileId];
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

  /// Stock on hand by id, for every product and variant of the shop.
  Future<Map<String, int>> getStockQtys(String profileId) async {
    final rows = await (await db).getAll(
      'SELECT id, stock_qty FROM product WHERE profile_id = ? '
      'UNION ALL SELECT id, stock_qty FROM product_variant WHERE profile_id = ?',
      [profileId, profileId],
    );
    return {for (final r in rows) r['id'] as String: r['stock_qty'] as int};
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

  /// Sets the stock of a product without variants, as a `correction` stock
  /// movement of the difference.
  Future<void> updateStock(String productId, int newQty) async {
    await (await db).writeTransaction((tx) async {
      final row = await tx.getOptional('SELECT profile_id, stock_qty FROM product WHERE id = ?', [productId]);
      if (row == null) return;
      if (await hasVariants(tx, productId)) {
        throw ArgumentError('Set the stock of its variants instead', 'productId');
      }
      final delta = newQty - (row['stock_qty'] as int);
      if (delta == 0) return;
      await recordStockMovement(tx,
          profileId: row['profile_id'] as String,
          productId: productId,
          delta: delta,
          reason: StockMovementReason.correction);
    });
  }

  /// Hides a product from inventory and POS. Products are never hard-deleted
  /// from the UI because sale_item rows reference them. Its image is removed:
  /// an archived product is not shown anywhere.
  Future<void> archive(String productId) async {
    final db = await this.db;
    await db.writeTransaction((tx) async {
      final imagePath = (await tx.getOptional('SELECT image_path FROM product WHERE id = ?', [productId]))?['image_path'];
      await tx.execute(
        'UPDATE product SET archived = 1, image_path = NULL, updated_at = ? WHERE id = ?',
        [toDbTime(DateTime.now()), productId],
      );
      if (imagePath is String) await queueImageDelete(tx, imagePath);
    });
  }

  /// Saves a product and (when [variants] is non-null) replaces its variant
  /// set, all in one transaction. Variants missing from [variants] are
  /// deleted; existing ones are updated in place.
  ///
  /// Stock is never written directly: the form's stock values become
  /// stock_movement rows (see StockMovementDao). A new product or variant
  /// starts at 0 with an `initial` movement; a changed value is a
  /// `correction` of the difference. A product with variants has stock_qty =
  /// sum of its variants' stock. When a product's last variants are removed,
  /// its stock restarts at 0 and the product's stockQty is a `conversion`
  /// movement.
  ///
  /// A changed [Product.imagePath] queues the file work for
  /// ProductImageStore: an upload of the new file and removal of the old one.
  /// The file itself must already be saved on the device.
  ///
  /// Throws [DataValidationException], [DuplicateCodeException] (another
  /// active product of the shop has the SKU or barcode), or, if [isNew] and
  /// the id exists, [DuplicateIdException]. Nothing is written then.
  Future<void> saveWithVariants(
    Product product, {
    required bool isNew,
    List<ProductVariant>? variants,
  }) async {
    validate(product);
    final db = await this.db;
    await db.writeTransaction((tx) async {
      final stored = isNew ? null : await tx.getOptional('SELECT * FROM product WHERE id = ?', [product.id]);
      if (!isNew && stored == null) return;
      final before = stored == null ? null : fromMap(stored);
      await _checkCodes(tx, product, before);

      if (isNew) {
        await insertRow(tx, tableName, {...product.toMap(), 'stock_qty': 0});
      } else {
        await updateRow(tx, tableName, product.id, product.toMap()..remove('stock_qty'));
      }
      final oldImage = before?.imagePath;
      if (product.imagePath != oldImage) {
        if (product.imagePath != null) await queueImageUpload(tx, product.imagePath!);
        if (oldImage != null) await queueImageDelete(tx, oldImage);
      }

      final hadVariants = await hasVariants(tx, product.id);
      if (variants != null) {
        await _saveVariants(tx, product, variants);
      }
      final hasVariantsNow = await hasVariants(tx, product.id);
      if (hasVariantsNow) return;

      // A product without variants: its stock field is the stock.
      final int delta;
      final StockMovementReason reason;
      if (isNew) {
        delta = product.stockQty;
        reason = StockMovementReason.initial;
      } else if (hadVariants) {
        // Removing the last variant left the stock at 0.
        delta = product.stockQty;
        reason = StockMovementReason.conversion;
      } else {
        final current = (await tx.get('SELECT stock_qty FROM product WHERE id = ?', [product.id]))['stock_qty'] as int;
        delta = product.stockQty - current;
        reason = StockMovementReason.correction;
      }
      if (delta != 0) {
        await recordStockMovement(tx,
            profileId: product.profileId, productId: product.id, delta: delta, reason: reason);
      }
    });
  }

  Future<void> _saveVariants(SqliteWriteContext tx, Product product, List<ProductVariant> variants) async {
    final keepIds = variants.map((v) => v.id).toSet();
    final existing = {
      for (final r in await tx.getAll('SELECT id, stock_qty FROM product_variant WHERE product_id = ?', [product.id]))
        r['id'] as String: r['stock_qty'] as int,
    };
    for (final id in existing.keys.where((id) => !keepIds.contains(id))) {
      await deleteVariantRow(tx, id);
    }
    for (final v in variants) {
      final variant = v.copyWith(productId: product.id, profileId: product.profileId);
      final current = existing[variant.id];
      if (current == null) {
        await insertRow(tx, 'product_variant', {...variant.toMap(), 'stock_qty': 0});
      } else {
        // The form does not carry created_at, so keep the stored one.
        await updateRow(tx, 'product_variant', variant.id, variant.toMap()..remove('stock_qty')..remove('created_at'));
      }
      final delta = variant.stockQty - (current ?? 0);
      if (delta != 0) {
        await recordStockMovement(tx,
            profileId: product.profileId,
            productId: product.id,
            variantId: variant.id,
            delta: delta,
            reason: current == null ? StockMovementReason.initial : StockMovementReason.correction);
      }
    }
    // With no variants left, the product's stock is not a variant total:
    // deleteVariantRow already zeroed it if the last one was removed here, and
    // a product that had none keeps its own.
    if (variants.isNotEmpty) await syncVariantStockTotal(tx, product.id);
  }

  /// Throws [DuplicateCodeException] if [product]'s SKU or barcode is used by
  /// another active product of the shop. Like the server's code check, only
  /// a new code (or un-archiving) is checked, so a duplicate that arrived by
  /// sync does not block other edits.
  Future<void> _checkCodes(SqliteWriteContext tx, Product product, Product? before) async {
    if (product.archived) return;
    final reactivated = before != null && before.archived;
    for (final (field, value, old) in [
      ('sku', product.sku, before?.sku),
      ('barcode', product.barcode, before?.barcode),
    ]) {
      if (value == null || (value == old && !reactivated && before != null)) continue;
      final other = await tx.getOptional(
        'SELECT 1 FROM product WHERE profile_id = ? AND archived = 0 AND $field = ? AND id <> ?',
        [product.profileId, value, product.id],
      );
      if (other != null) throw DuplicateCodeException(field, value);
    }
  }
}
