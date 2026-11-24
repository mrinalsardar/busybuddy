import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';

/// True while the active profile has no products or sales, so its currency
/// and decimals can still change. Auto-disposed so it is re-checked each time
/// Settings opens.
final canEditCurrencyProvider = FutureProvider.autoDispose<bool>((ref) async {
  final profile = ref.watch(activeProfileProvider).value;
  if (profile == null) return false;
  return !await ref.read(businessProfileDaoProvider).hasProductsOrSales(profile.id);
});
