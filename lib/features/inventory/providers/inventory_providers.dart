import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_variant.dart';
import '../../../core/providers/core_providers.dart';

// ── Search / filter state ──────────────────────────────
final inventorySearchProvider = StateProvider<String>((_) => '');
final inventoryCategoryFilterProvider = StateProvider<String?>((_) => null);

// ── Product list ───────────────────────────────────────
final productListProvider = FutureProvider<List<Product>>((ref) async {
  final profile = ref.watch(activeProfileProvider).value;
  if (profile == null) return [];

  final search = ref.watch(inventorySearchProvider);
  final category = ref.watch(inventoryCategoryFilterProvider);
  final dao = ref.read(productDaoProvider);

  return dao.getByProfile(
    profile.id,
    category: category,
    searchQuery: search.isEmpty ? null : search,
  );
});

// ── POS product list ───────────────────────────────────
/// All active products for the POS grid. Unlike [productListProvider] it
/// ignores the Inventory search and category filters.
final posProductListProvider = FutureProvider<List<Product>>((ref) async {
  final profile = ref.watch(activeProfileProvider).value;
  if (profile == null) return [];
  return ref.read(productDaoProvider).getByProfile(profile.id);
});

/// Refreshes every view of product data and stock. Call after any write to
/// products, variants or sales: `invalidateProductViews(ref.invalidate)`.
void invalidateProductViews(void Function(ProviderOrFamily) invalidate) {
  invalidate(productListProvider);
  invalidate(posProductListProvider);
  invalidate(categoryListProvider);
  invalidate(productByIdProvider);
  invalidate(variantsProvider);
  invalidate(lowStockCountProvider);
  invalidate(avgSellingPriceProvider);
}

// ── Average selling price ──────────────────────────────
/// Product id -> average actual selling price (minor units) from past sales.
final avgSellingPriceProvider = FutureProvider<Map<String, int>>((ref) async {
  final profile = ref.watch(activeProfileProvider).value;
  if (profile == null) return {};
  return ref.read(saleItemDaoProvider).getAvgSellingPricesMinor(profile.id);
});

// ── Category list ──────────────────────────────────────
final categoryListProvider = FutureProvider<List<String>>((ref) async {
  final profile = ref.watch(activeProfileProvider).value;
  if (profile == null) return [];
  return ref.read(productDaoProvider).getCategories(profile.id);
});

// ── Single product ─────────────────────────────────────
final productByIdProvider =
    FutureProvider.family<Product?, String>((ref, id) async {
  return ref.read(productDaoProvider).getById(id);
});

// ── Variants for a product ─────────────────────────────
final variantsProvider =
    FutureProvider.family<List<ProductVariant>, String>((ref, productId) async {
  return ref.read(productVariantDaoProvider).getByProduct(productId);
});

// ── Low-stock count ────────────────────────────────────
final lowStockCountProvider = FutureProvider<int>((ref) async {
  final profile = ref.watch(activeProfileProvider).value;
  if (profile == null) return 0;
  final items = await ref.read(productDaoProvider).getLowStock(profile.id);
  return items.length;
});
