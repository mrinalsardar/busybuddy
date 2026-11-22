import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

class Product extends Equatable {
  final String id;
  final String profileId;
  final String name;
  final String? sku;
  final String? barcode;
  /// Selling price in minor units (see core/utils/money.dart).
  final int priceMinor;
  final int costPriceMinor;
  final String? category;
  final int stockQty;
  final int lowStockThreshold;
  final DateTime? expiryDate;
  final String? imagePath;
  final bool archived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Product({
    required this.id,
    required this.profileId,
    required this.name,
    this.sku,
    this.barcode,
    this.priceMinor = 0,
    this.costPriceMinor = 0,
    this.category,
    this.stockQty = 0,
    this.lowStockThreshold = 5,
    this.expiryDate,
    this.imagePath,
    this.archived = false,
    this.createdAt,
    this.updatedAt,
  });

  bool get isLowStock => stockQty <= lowStockThreshold;

  Product copyWith({
    String? id,
    String? profileId,
    String? name,
    String? sku,
    String? barcode,
    int? priceMinor,
    int? costPriceMinor,
    String? category,
    int? stockQty,
    int? lowStockThreshold,
    DateTime? expiryDate,
    String? imagePath,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      priceMinor: priceMinor ?? this.priceMinor,
      costPriceMinor: costPriceMinor ?? this.costPriceMinor,
      category: category ?? this.category,
      stockQty: stockQty ?? this.stockQty,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      expiryDate: expiryDate ?? this.expiryDate,
      imagePath: imagePath ?? this.imagePath,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profile_id': profileId,
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'price_minor': priceMinor,
      'cost_price_minor': costPriceMinor,
      'category': category,
      'stock_qty': stockQty,
      'low_stock_threshold': lowStockThreshold,
      'expiry_date': expiryDate == null ? null : toDbDate(expiryDate!),
      'image_path': imagePath,
      'archived': archived ? 1 : 0,
      'created_at': toDbTime(createdAt ?? DateTime.now()),
      'updated_at': toDbTime(updatedAt ?? DateTime.now()),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      name: map['name'] as String,
      sku: map['sku'] as String?,
      barcode: map['barcode'] as String?,
      priceMinor: map['price_minor'] as int? ?? 0,
      costPriceMinor: map['cost_price_minor'] as int? ?? 0,
      category: map['category'] as String?,
      stockQty: map['stock_qty'] as int? ?? 0,
      lowStockThreshold: map['low_stock_threshold'] as int? ?? 5,
      expiryDate: fromDbDate(map['expiry_date']),
      imagePath: map['image_path'] as String?,
      archived: (map['archived'] as int? ?? 0) == 1,
      createdAt: fromDbTime(map['created_at']),
      updatedAt: fromDbTime(map['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => toMap();
  factory Product.fromJson(Map<String, dynamic> json) =>
      Product.fromMap(json);

  @override
  List<Object?> get props => [id, profileId, name, sku, barcode, priceMinor, costPriceMinor, stockQty, archived];
}
