import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

class ProductVariant extends Equatable {
  final String id;
  final String productId;
  final String? size;
  final String? color;
  final int stockQty;
  final DateTime? createdAt;

  const ProductVariant({
    required this.id,
    required this.productId,
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
    String? size,
    String? color,
    int? stockQty,
    DateTime? createdAt,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      productId: productId ?? this.productId,
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
  List<Object?> get props => [id, productId, size, color, stockQty];
}
