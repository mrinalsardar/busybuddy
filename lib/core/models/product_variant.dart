import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

class ProductVariant extends Equatable {
  final String id;
  final String productId;
  /// The product's shop (business_profile id).
  final String profileId;
  final String? size;
  final String? color;
  final int stockQty;
  final DateTime? createdAt;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.profileId,
    this.size,
    this.color,
    this.stockQty = 0,
    this.createdAt,
  });

  String get displayName {
    final parts = <String>[];
    if (size != null && size!.isNotEmpty) parts.add(size!);
    if (color != null && color!.isNotEmpty) parts.add(color!);
    return parts.join(' / ');
  }

  ProductVariant copyWith({
    String? id,
    String? productId,
    String? profileId,
    String? size,
    String? color,
    int? stockQty,
    DateTime? createdAt,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      profileId: profileId ?? this.profileId,
      size: size ?? this.size,
      color: color ?? this.color,
      stockQty: stockQty ?? this.stockQty,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'profile_id': profileId,
      'size': size,
      'color': color,
      'stock_qty': stockQty,
      'created_at': toDbTime(createdAt ?? DateTime.now()),
    };
  }

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      profileId: map['profile_id'] as String,
      size: map['size'] as String?,
      color: map['color'] as String?,
      stockQty: map['stock_qty'] as int? ?? 0,
      createdAt: fromDbTime(map['created_at']),
    );
  }

  Map<String, dynamic> toJson() => toMap();
  factory ProductVariant.fromJson(Map<String, dynamic> json) =>
      ProductVariant.fromMap(json);

  @override
  List<Object?> get props => [id, productId, profileId, size, color, stockQty];
}
