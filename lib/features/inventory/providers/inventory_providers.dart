import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_variant.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/watch_tables.dart';

// ── Search / filter state ──────────────────────────────
final inventorySearchProvider = StateProvider<String>((_) => '');
final inventoryCategoryFilterProvider = StateProvider<String?>((_) => null);

// ── Product list ───────────────────────────────────────
final productListProvider = FutureProvider<List<Product>>((ref) async {
  watchTables(ref, {'product'});
  final profileId = ref.watch(activeProfileIdProvider);
  if (profileId == null) return [];

  final search = ref.watch(inventorySearchProvider);
  final category = ref.watch(inventoryCategoryFilterProvider);
  final dao = ref.read(productDaoProvider);

  return dao.getByProfile(
    profileId,
    category: category,
    searchQuery: search.isEmpty ? null : search,
  );
});

// ── POS product list ───────────────────────────────────
/// All active products for the POS grid. Unlike [productListProvider] it
/// ignores the Inventory search and category filters.
final posProductListProvider = FutureProvider<List<Product>>((ref) async {
  watchTables(ref, {'product'});
  final profileId = ref.watch(activeProfileIdProvider);
  if (profileId == null) return [];
  return ref.read(productDaoProvider).getByProfile(profileId);
});

/// Refreshes every view of product data and stock. Call after any write to
/// products, variants or sales: `invalidateProductViews(ref.invalidate)`.
/// The views also follow table changes by themselves (see [watchTables]);
/// this refreshes them without waiting for the change notification.
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
  watchTables(ref, {'sale', 'sale_item'});
  final profileId = ref.watch(activeProfileIdProvider);
  if (profileId == null) return {};
  return ref.read(saleItemDaoProvider).getAvgSellingPricesMinor(profileId);
});

// ── Category list ──────────────────────────────────────
/// Auto-disposed, so each open of the filter sheet queries again and never
/// starts from an old list.
final categoryListProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  watchTables(ref, {'product'});
  final profileId = ref.watch(activeProfileIdProvider);
  if (profileId == null) return [];
  return ref.read(productDaoProvider).getCategories(profileId);
});

// ── Single product ─────────────────────────────────────
final productByIdProvider =
    FutureProvider.family<Product?, String>((ref, id) async {
  watchTables(ref, {'product'});
  return ref.read(productDaoProvider).getById(id);
});

// ── Variants for a product ─────────────────────────────
final variantsProvider =
    FutureProvider.family<List<ProductVariant>, String>((ref, productId) async {
  watchTables(ref, {'product_variant'});
  return ref.read(productVariantDaoProvider).getByProduct(productId);
});

// ── Low-stock count ────────────────────────────────────
final lowStockCountProvider = FutureProvider<int>((ref) async {
  watchTables(ref, {'product'});
  final profileId = ref.watch(activeProfileIdProvider);
  if (profileId == null) return 0;
  final items = await ref.read(productDaoProvider).getLowStock(profileId);
  return items.length;
});
