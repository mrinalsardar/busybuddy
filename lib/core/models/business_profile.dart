import 'package:equatable/equatable.dart';
import '../db/db_time.dart';
import '../utils/money.dart';

/// The four supported business types.
enum BusinessType { shoes, fashion, grocery, general }

extension BusinessTypeX on BusinessType {
  String get label {
    switch (this) {
      case BusinessType.shoes:
        return 'Shoes';
      case BusinessType.fashion:
        return 'Fashion';
      case BusinessType.grocery:
        return 'Grocery';
      case BusinessType.general:
        return 'General Retail';
    }
  }

  String get icon {
    switch (this) {
      case BusinessType.shoes:
        return '👟';
      case BusinessType.fashion:
        return '👗';
      case BusinessType.grocery:
        return '🛒';
      case BusinessType.general:
        return '🏪';
    }
  }

  /// Shoes & fashion get variant support (size/colour).
  bool get hasVariantSupport =>
      this == BusinessType.shoes || this == BusinessType.fashion;

  /// Grocery gets expiry-date tracking.
  bool get hasExpiryTracking => this == BusinessType.grocery;
}

/// Domain model for the business_profile table.
class BusinessProfile extends Equatable {
  final String id;
  final String name;
  final BusinessType type;
  final String currency;
  final String taxLabel;
  final int themeColor;
  final bool variantSupport;
  final bool expiryTracking;
  /// When true a sale may take stock below 0; otherwise it is rejected.
  final bool allowOversell;
  /// 0 to 3. Locked once the profile has products or sales.
  final int currencyDecimals;
  final String? googleAccountId;
  final DateTime? createdAt;

  const BusinessProfile({
    required this.id,
    required this.name,
    required this.type,
    this.currency = 'INR',
    this.taxLabel = 'GST',
    this.themeColor = 0xFF6C63FF,
    this.variantSupport = false,
    this.expiryTracking = false,
    this.allowOversell = false,
    this.currencyDecimals = 2,
    this.googleAccountId,
    this.createdAt,
  });

  BusinessProfile copyWith({
    String? id,
    String? name,
    BusinessType? type,
    String? currency,
    String? taxLabel,
    int? themeColor,
    bool? variantSupport,
    bool? expiryTracking,
    bool? allowOversell,
    int? currencyDecimals,
    String? googleAccountId,
    DateTime? createdAt,
  }) {
    return BusinessProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      taxLabel: taxLabel ?? this.taxLabel,
      themeColor: themeColor ?? this.themeColor,
      variantSupport: variantSupport ?? this.variantSupport,
      expiryTracking: expiryTracking ?? this.expiryTracking,
      allowOversell: allowOversell ?? this.allowOversell,
      currencyDecimals: currencyDecimals ?? this.currencyDecimals,
      googleAccountId: googleAccountId ?? this.googleAccountId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'currency': currency,
      'tax_label': taxLabel,
      'theme_color': themeColor,
      'variant_support': variantSupport ? 1 : 0,
      'expiry_tracking': expiryTracking ? 1 : 0,
      'allow_oversell': allowOversell ? 1 : 0,
      'currency_decimals': currencyDecimals,
      'google_account_id': googleAccountId,
      'created_at': toDbTime(createdAt ?? DateTime.now()),
    };
  }

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      type: BusinessType.values.firstWhere((e) => e.name == map['type']),
      currency: map['currency'] as String? ?? 'INR',
      taxLabel: map['tax_label'] as String? ?? 'GST',
      themeColor: map['theme_color'] as int? ?? 0xFF6C63FF,
      variantSupport: (map['variant_support'] as int? ?? 0) == 1,
      expiryTracking: (map['expiry_tracking'] as int? ?? 0) == 1,
      allowOversell: (map['allow_oversell'] as int? ?? 0) == 1,
      currencyDecimals: map['currency_decimals'] as int? ?? 2,
      googleAccountId: map['google_account_id'] as String?,
      createdAt: fromDbTime(map['created_at']),
    );
  }

  Map<String, dynamic> toJson() => toMap();
  factory BusinessProfile.fromJson(Map<String, dynamic> json) =>
      BusinessProfile.fromMap(json);

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        currency,
        taxLabel,
        themeColor,
        variantSupport,
        expiryTracking,
        allowOversell,
        currencyDecimals,
        googleAccountId,
      ];

  MoneyFormat get money => MoneyFormat(currency, currencyDecimals);
}
