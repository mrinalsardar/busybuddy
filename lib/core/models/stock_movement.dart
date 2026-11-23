import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

/// Why stock changed. Matches the server's `stock_movement.reason` check.
enum StockMovementReason { initial, restock, correction, sale, conversion }

/// One entry of the append-only stock ledger: a relative change of a
/// product's or variant's stock. Never updated or deleted.
class StockMovement extends Equatable {
  /// Client-generated UUID, so a retried upload changes nothing. Sale
  /// movements are written by the server with id `'sale:' || sale_item.id`.
  final String id;
  final String profileId;
  final String productId;
  /// The variant whose stock changes, or null for a product without variants.
  final String? variantId;
  /// Positive adds stock, negative removes it.
  final int delta;
  final StockMovementReason reason;
  final String? saleId;
  /// Supabase user id; set by the server.
  final String? createdBy;
  final DateTime? createdAt;

  const StockMovement({
    required this.id,
    required this.profileId,
    required this.productId,
    this.variantId,
    required this.delta,
    required this.reason,
    this.saleId,
    this.createdBy,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'profile_id': profileId,
        'product_id': productId,
        'variant_id': variantId,
        'delta': delta,
        'reason': reason.name,
        'sale_id': saleId,
        'created_by': createdBy,
        'created_at': toDbTime(createdAt ?? DateTime.now()),
      };

  factory StockMovement.fromMap(Map<String, dynamic> map) => StockMovement(
        id: map['id'] as String,
        profileId: map['profile_id'] as String,
        productId: map['product_id'] as String,
        variantId: map['variant_id'] as String?,
        delta: map['delta'] as int,
        reason: StockMovementReason.values.byName(map['reason'] as String),
        saleId: map['sale_id'] as String?,
        createdBy: map['created_by'] as String?,
        createdAt: fromDbTime(map['created_at']),
      );

  @override
  List<Object?> get props => [id, profileId, productId, variantId, delta, reason, saleId];
}
