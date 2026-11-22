import 'package:equatable/equatable.dart';

class SaleItem extends Equatable {
  final String id;
  final String saleId;
  final String productId;
  /// Product (and variant) name at time of sale, so history survives renames/archiving.
  final String productName;
  final String? variantId;
  final int qty;
  /// Price and cost at time of sale, in minor units.
  final int unitPriceMinor;
  final int costPriceMinor;

  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.productName,
    this.variantId,
    this.qty = 1,
    this.unitPriceMinor = 0,
    this.costPriceMinor = 0,
  });

  int get lineTotalMinor => qty * unitPriceMinor;

  SaleItem copyWith({
    String? id,
    String? saleId,
    String? productId,
    String? productName,
    String? variantId,
    int? qty,
    int? unitPriceMinor,
    int? costPriceMinor,
  }) {
    return SaleItem(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      variantId: variantId ?? this.variantId,
      qty: qty ?? this.qty,
      unitPriceMinor: unitPriceMinor ?? this.unitPriceMinor,
      costPriceMinor: costPriceMinor ?? this.costPriceMinor,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'sale_id': saleId, 'product_id': productId, 'product_name': productName,
    'variant_id': variantId, 'qty': qty,
    'unit_price_minor': unitPriceMinor, 'cost_price_minor': costPriceMinor,
  };

  factory SaleItem.fromMap(Map<String, dynamic> map) => SaleItem(
    id: map['id'] as String,
    saleId: map['sale_id'] as String,
    productId: map['product_id'] as String,
    productName: map['product_name'] as String,
    variantId: map['variant_id'] as String?,
    qty: map['qty'] as int? ?? 1,
    unitPriceMinor: map['unit_price_minor'] as int? ?? 0,
    costPriceMinor: map['cost_price_minor'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => toMap();
  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem.fromMap(json);

  @override
  List<Object?> get props => [id, saleId, productId, productName, qty, unitPriceMinor, costPriceMinor];
}
