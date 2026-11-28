import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/watch_tables.dart';

/// True while the active profile has no products or sales, so its currency
/// and decimals can still change. Auto-disposed so it is re-checked each time
/// Settings opens.
final canEditCurrencyProvider = FutureProvider.autoDispose<bool>((ref) async {
  watchTables(ref, {'product', 'sale'});
  final profileId = ref.watch(activeProfileIdProvider);
  if (profileId == null) return false;
  return !await ref.read(businessProfileDaoProvider).hasProductsOrSales(profileId);
});
