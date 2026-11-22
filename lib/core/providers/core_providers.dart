import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dao/business_profile_dao.dart';
import '../dao/product_dao.dart';
import '../dao/product_variant_dao.dart';
import '../dao/sale_dao.dart';
import '../dao/sale_item_dao.dart';
import '../dao/customer_dao.dart';
import '../dao/expense_dao.dart';
import '../dao/supplier_dao.dart';
import '../dao/backup_log_dao.dart';
import '../models/business_profile.dart';

// ── DAO providers (singletons) ─────────────────────────
final businessProfileDaoProvider = Provider((_) => BusinessProfileDao());
final productDaoProvider = Provider((_) => ProductDao());
final productVariantDaoProvider = Provider((_) => ProductVariantDao());
final saleDaoProvider = Provider((_) => SaleDao());
final saleItemDaoProvider = Provider((_) => SaleItemDao());
final customerDaoProvider = Provider((_) => CustomerDao());
final expenseDaoProvider = Provider((_) => ExpenseDao());
final supplierDaoProvider = Provider((_) => SupplierDao());
final backupLogDaoProvider = Provider((_) => BackupLogDao());

// ── Active profile ─────────────────────────────────────
/// Holds the current BusinessProfile once loaded. Null means onboarding needed.
final activeProfileProvider =
    StateNotifierProvider<ActiveProfileNotifier, AsyncValue<BusinessProfile?>>(
  (ref) => ActiveProfileNotifier(ref.read(businessProfileDaoProvider)),
);

class ActiveProfileNotifier extends StateNotifier<AsyncValue<BusinessProfile?>> {
  final BusinessProfileDao _dao;

  ActiveProfileNotifier(this._dao) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _dao.getActiveProfile();
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> setProfile(BusinessProfile profile) async {
    await _dao.insert(profile);
    state = AsyncValue.data(profile);
  }

  /// Saves changed settings of the existing profile. Throws [StateError] if
  /// the currency or its decimals change after products or sales exist,
  /// because stored minor-unit amounts would be rescaled.
  Future<void> updateProfile(BusinessProfile profile) async {
    final current = state.valueOrNull;
    final currencyChanged = current != null &&
        (current.currency != profile.currency ||
            current.currencyDecimals != profile.currencyDecimals);
    if (currencyChanged && await _dao.hasProductsOrSales(profile.id)) {
      throw StateError('Currency is locked once products or sales exist');
    }
    await _dao.update(profile, profile.id);
    state = AsyncValue.data(profile);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }
}
