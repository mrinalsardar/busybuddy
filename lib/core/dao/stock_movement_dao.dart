import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;
import 'package:uuid/uuid.dart';
import '../db/base_dao.dart';
import '../models/stock_movement.dart';

/// The stock ledger. Stock is never set directly: every change (opening
/// stock, restock, correction, variant-to-plain conversion) is a new
/// stock_movement row, which uploads with a unique id so the server applies it
/// exactly once, relative to whatever other devices did. The server computes
/// stock_qty from the movements; the client never uploads it.
///
/// So the device shows a change at once, [recordStockMovement] also applies
/// the movement to the local stock_qty, the way the server's
/// stock_movement_apply trigger does. The next sync replaces the local value
/// with the server's.
class StockMovementDao extends BaseDao<StockMovement> {
  @override
  String get tableName => 'stock_movement';

  @override
  Map<String, dynamic> toMap(StockMovement item) => item.toMap();

  @override
  StockMovement fromMap(Map<String, dynamic> map) => StockMovement.fromMap(map);

  /// Records [item] and applies it to the local stock.
  @override
  Future<int> insert(StockMovement item) async {
    await (await db).writeTransaction((tx) => _insertAndApply(tx, item));
    return 1;
  }

  /// Records a stock change, e.g. a restock (positive [delta]) or a
  /// correction, for [variantId] or, if null, a product without variants.
  Future<void> record({
    required String profileId,
    required String productId,
    String? variantId,
    required int delta,
    required StockMovementReason reason,
  }) async {
    await (await db).writeTransaction((tx) => recordStockMovement(tx,
        profileId: profileId, productId: productId, variantId: variantId, delta: delta, reason: reason));
  }

  @override
  Future<int> update(StockMovement item, String id) =>
      throw UnsupportedError('Stock movements are never updated; record a new one');

  @override
  Future<int> delete(String id) =>
      throw UnsupportedError('Stock movements are never deleted; record a new one');

  Future<List<StockMovement>> getByProduct(String productId) =>
      query(where: 'product_id = ?', whereArgs: [productId], orderBy: 'created_at ASC');
}

/// Inserts a movement and applies it to the local stock (see
/// [StockMovementDao]). For use inside a write transaction.
Future<void> recordStockMovement(
  SqliteWriteContext tx, {
  required String profileId,
  required String productId,
  String? variantId,
  required int delta,
  required StockMovementReason reason,
}) =>
    _insertAndApply(
        tx,
        StockMovement(
          id: const Uuid().v4(),
          profileId: profileId,
          productId: productId,
          variantId: variantId,
          delta: delta,
          reason: reason,
          createdAt: DateTime.now(),
        ));

Future<void> _insertAndApply(SqliteWriteContext tx, StockMovement m) async {
  await insertRow(tx, 'stock_movement', m.toMap());

  // Mirrors stock_movement_apply: a movement for a variant of the product
  // changes that variant, and the product total follows; one without a
  // variant changes a product that has no variants. Anything else changes
  // nothing (the server flags it in stock_alert).
  final product = await tx.getOptional(
      'SELECT id FROM product WHERE id = ? AND profile_id = ?', [m.productId, m.profileId]);
  if (product == null) return;
  if (m.variantId != null) {
    final variant = await tx.getOptional(
        'SELECT id FROM product_variant WHERE id = ? AND product_id = ?', [m.variantId, m.productId]);
    if (variant == null) return;
    await tx.execute(
        'UPDATE product_variant SET stock_qty = stock_qty + ? WHERE id = ?', [m.delta, m.variantId]);
    await syncVariantStockTotal(tx, m.productId);
  } else if (!await hasVariants(tx, m.productId)) {
    await tx.execute('UPDATE product SET stock_qty = stock_qty + ? WHERE id = ?', [m.delta, m.productId]);
  }
}

Future<bool> hasVariants(SqliteWriteContext tx, String productId) async =>
    await tx.getOptional('SELECT 1 FROM product_variant WHERE product_id = ?', [productId]) != null;

/// Sets a product's stock to the sum of its variants' stock (0 if it has
/// none), as the server's product_variant_stock trigger does after every
/// variant insert, delete or stock change.
///
/// Stock writes leave updated_at alone, so they add nothing to the upload
/// beyond stock_qty, which the connector drops.
Future<void> syncVariantStockTotal(SqliteWriteContext tx, String productId) async {
  await tx.execute(
    'UPDATE product SET stock_qty = '
    '(SELECT COALESCE(SUM(stock_qty), 0) FROM product_variant WHERE product_id = ?) '
    'WHERE id = ?',
    [productId, productId],
  );
}
