import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_repository.dart';
import '../db/database_helper.dart';
import '../dao/business_profile_dao.dart';
import '../dao/product_dao.dart';
import '../dao/product_variant_dao.dart';
import '../dao/sale_dao.dart';
import '../dao/sale_item_dao.dart';
import '../dao/customer_dao.dart';
import '../dao/expense_dao.dart';
import '../dao/supplier_dao.dart';
import '../dao/stock_movement_dao.dart';
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
final stockMovementDaoProvider = Provider((_) => StockMovementDao());
final backupLogDaoProvider = Provider((_) => BackupLogDao());

// ── Auth ───────────────────────────────────────────────
/// The backend account calls. Overridden in main with the Supabase one when a
/// backend is configured; otherwise the app runs on the local database only.
final authRepositoryProvider = Provider<AuthRepository>((_) => const LocalAuthRepository());

/// Id of the signed-in user. Null when signed out, and always null without a
/// backend.
final authProvider = StateNotifierProvider<AuthNotifier, String?>(
  (ref) => AuthNotifier(ref.watch(authRepositoryProvider)),
);

class AuthNotifier extends StateNotifier<String?> {
  AuthNotifier(AuthRepository repo) : super(repo.userId) {
    _sub = repo.userChanges.listen((id) {
      if (id != state) state = id;
    });
  }

  late final StreamSubscription<String?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// What the app needs to know of the sync with the server.
class SyncState {
  const SyncState({this.lastSyncedAt});

  /// When a sync last completed; null if this device has never synced.
  final DateTime? lastSyncedAt;

  /// True once this device has downloaded its shop data at least once.
  bool get hasSynced => lastSyncedAt != null;
}

/// Emits again whenever a sync completes (or the local data is cleared).
final syncStateProvider = StreamProvider<SyncState>((ref) async* {
  final db = await DatabaseHelper().database;
  var last = db.currentStatus.lastSyncedAt;
  yield SyncState(lastSyncedAt: last);
  await for (final status in db.statusStream) {
    if (status.lastSyncedAt == last) continue;
    last = status.lastSyncedAt;
    yield SyncState(lastSyncedAt: last);
  }
});

// ── Active profile ─────────────────────────────────────
/// Holds the current BusinessProfile once loaded. Null means onboarding needed.
/// Rebuilt when the signed-in user changes, and re-read after each sync, since
/// a sync can bring the user's shop (first sign-in on a device, a join) or
/// change its settings.
final activeProfileProvider =
    StateNotifierProvider<ActiveProfileNotifier, AsyncValue<BusinessProfile?>>((ref) {
  final notifier = ActiveProfileNotifier(
    ref.read(businessProfileDaoProvider),
    userId: ref.watch(authProvider),
  );
  ref.listen<AsyncValue<SyncState>>(syncStateProvider, (prev, next) {
    final at = next.valueOrNull?.lastSyncedAt;
    if (at != null && at != prev?.valueOrNull?.lastSyncedAt) notifier.reloadAfterSync();
  });
  return notifier;
});

class ActiveProfileNotifier extends StateNotifier<AsyncValue<BusinessProfile?>> {
  final BusinessProfileDao _dao;
  final String? _userId;

  ActiveProfileNotifier(this._dao, {String? userId})
      : _userId = userId,
        super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _dao.getActiveProfile(userId: _userId);
      if (mounted) state = AsyncValue.data(profile);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  /// Re-reads the profile after a sync. While there is no profile, the state
  /// is loading until the read finishes, so the router does not send the user
  /// to onboarding in between. A profile that did not change keeps its state,
  /// so nothing downstream reloads.
  Future<void> reloadAfterSync() async {
    if (state.valueOrNull == null) state = const AsyncValue.loading();
    try {
      final profile = await _dao.getActiveProfile(userId: _userId);
      if (!mounted) return;
      final current = state;
      if (current is AsyncData<BusinessProfile?> && current.value == profile) return;
      state = AsyncValue.data(profile);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
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

// ── Role ───────────────────────────────────────────────
enum ShopRole { owner, staff }

/// The signed-in user's role in the active shop. A shop with no synced
/// membership row was created on this device, by its owner. Without a backend
/// the user owns the shop.
final shopRoleProvider = FutureProvider<ShopRole>((ref) async {
  final profile = ref.watch(activeProfileProvider).valueOrNull;
  final userId = ref.watch(authProvider);
  // A sync can change memberships, e.g. a promotion.
  ref.watch(syncStateProvider.select((s) => s.valueOrNull?.lastSyncedAt));
  if (profile == null || userId == null) return ShopRole.owner;
  final role = await ref.read(businessProfileDaoProvider).getMemberRole(profile.id, userId);
  return role == 'staff' ? ShopRole.staff : ShopRole.owner;
});

/// True once the role is known to be owner. Staff-restricted UI (shop
/// settings, cost prices) stays hidden until then.
final isOwnerProvider =
    Provider<bool>((ref) => ref.watch(shopRoleProvider).valueOrNull == ShopRole.owner);
