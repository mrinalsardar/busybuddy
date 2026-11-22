import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

class Sale extends Equatable {
  final String id;
  final String profileId;
  final String? customerId;
  final DateTime createdAt;
  // Amounts in minor units (see core/utils/money.dart).
  final int subtotalMinor;
  final int taxAmountMinor;
  final int discountMinor;
  final int totalMinor;
  final String paymentMethod;

  const Sale({
    required this.id,
    required this.profileId,
    this.customerId,
    required this.createdAt,
    this.subtotalMinor = 0,
    this.taxAmountMinor = 0,
    this.discountMinor = 0,
    this.totalMinor = 0,
    this.paymentMethod = 'cash',
  });

  Sale copyWith({
    String? id,
    String? profileId,
    String? customerId,
    DateTime? createdAt,
    int? subtotalMinor,
    int? taxAmountMinor,
    int? discountMinor,
    int? totalMinor,
    String? paymentMethod,
  }) {
    return Sale(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      customerId: customerId ?? this.customerId,
      createdAt: createdAt ?? this.createdAt,
      subtotalMinor: subtotalMinor ?? this.subtotalMinor,
      taxAmountMinor: taxAmountMinor ?? this.taxAmountMinor,
      discountMinor: discountMinor ?? this.discountMinor,
      totalMinor: totalMinor ?? this.totalMinor,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profile_id': profileId,
      'customer_id': customerId,
      'created_at': toDbTime(createdAt),
      'subtotal_minor': subtotalMinor,
      'tax_amount_minor': taxAmountMinor,
      'discount_minor': discountMinor,
      'total_minor': totalMinor,
      'payment_method': paymentMethod,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      customerId: map['customer_id'] as String?,
      createdAt: fromDbTime(map['created_at'])!,
      subtotalMinor: map['subtotal_minor'] as int? ?? 0,
      taxAmountMinor: map['tax_amount_minor'] as int? ?? 0,
      discountMinor: map['discount_minor'] as int? ?? 0,
      totalMinor: map['total_minor'] as int? ?? 0,
      paymentMethod: map['payment_method'] as String? ?? 'cash',
    );
  }

  Map<String, dynamic> toJson() => toMap();
  factory Sale.fromJson(Map<String, dynamic> json) => Sale.fromMap(json);

  @override
  List<Object?> get props => [id, profileId, totalMinor, createdAt];
}
