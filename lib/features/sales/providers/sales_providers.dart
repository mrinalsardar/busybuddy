import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_variant.dart';
import '../../../core/models/sale.dart';
import '../../../core/models/sale_item.dart';
import '../../../core/providers/core_providers.dart';
import '../../inventory/providers/inventory_providers.dart';

/// A single item in the POS cart.
class CartItem {
  final Product product;
  final ProductVariant? variant;
  int qty;

  /// Actual price per unit for this sale. Starts at the product's suggested
  /// price and can be changed at the counter.
  int unitPriceMinor;

  CartItem({required this.product, this.variant, this.qty = 1})
      : unitPriceMinor = product.priceMinor;

  int get lineTotalMinor => qty * unitPriceMinor;

  /// Stock on hand when the item was added. Checkout re-checks it in the DB.
  int get available => variant?.stockQty ?? product.stockQty;

  String get displayName {
    if (variant != null && variant!.displayName.isNotEmpty) {
      return '${product.name} (${variant!.displayName})';
    }
    return product.name;
  }

  /// Unique key for deduplication in cart.
  String get cartKey => variant != null ? '${product.id}_${variant!.id}' : product.id;
}

/// The cart state notifier.
class CartNotifier extends ChangeNotifier {
  CartNotifier({bool Function()? allowOversell})
      : _allowOversell = allowOversell ?? (() => false);

  /// Read on every add, so a settings change applies to the open cart.
  final bool Function() _allowOversell;
  final List<CartItem> _items = [];
  int _discountMinor = 0;
  String _paymentMethod = 'cash';
  bool _checkingOut = false;

  List<CartItem> get items => List.unmodifiable(_items);

  /// True while a checkout is being written; the Charge button is disabled
  /// and further checkouts are ignored so a double tap can't record twice.
  bool get isCheckingOut => _checkingOut;

  void _setCheckingOut(bool value) {
    _checkingOut = value;
    notifyListeners();
  }
  int get discountMinor => _discountMinor;
  String get paymentMethod => _paymentMethod;

  int get subtotalMinor =>
      _items.fold(0, (sum, item) => sum + item.lineTotalMinor);

  int get totalMinor {
    final total = subtotalMinor - _discountMinor;
    return total < 0 ? 0 : total;
  }

  int get itemCount => _items.fold(0, (sum, item) => sum + item.qty);

  /// Adds one unit. Returns false (and changes nothing) if that would exceed
  /// the stock on hand and oversells aren't allowed.
  bool addItem(Product product, {ProductVariant? variant}) {
    final key = variant != null ? '${product.id}_${variant.id}' : product.id;
    final idx = _items.indexWhere((i) => i.cartKey == key);
    if (idx >= 0) {
      if (!_allowOversell() && _items[idx].qty >= _items[idx].available) return false;
      _items[idx].qty++;
    } else {
      final item = CartItem(product: product, variant: variant);
      if (!_allowOversell() && item.available < 1) return false;
      _items.add(item);
    }
    notifyListeners();
    return true;
  }

  void removeItem(String cartKey) {
    _items.removeWhere((i) => i.cartKey == cartKey);
    notifyListeners();
  }

  /// Sets a line's quantity; 0 or less removes it. Returns false (and changes
  /// nothing) if [qty] exceeds the stock on hand and oversells aren't allowed.
  bool updateQty(String cartKey, int qty) {
    final idx = _items.indexWhere((i) => i.cartKey == cartKey);
    if (idx < 0) return true;
    if (qty <= 0) {
      _items.removeAt(idx);
    } else {
      if (!_allowOversell() && qty > _items[idx].available) return false;
      _items[idx].qty = qty;
    }
    notifyListeners();
    return true;
  }

  /// Sets the actual unit price of a line. Negative prices are ignored.
  void updatePrice(String cartKey, int unitPriceMinor) {
    final idx = _items.indexWhere((i) => i.cartKey == cartKey);
    if (idx < 0 || unitPriceMinor < 0) return;
    _items[idx].unitPriceMinor = unitPriceMinor;
    notifyListeners();
  }

  void setDiscountMinor(int d) {
    _discountMinor = d;
    notifyListeners();
  }

  void setPaymentMethod(String m) {
    _paymentMethod = m;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _discountMinor = 0;
    _paymentMethod = 'cash';
    notifyListeners();
  }
}

final cartProvider = ChangeNotifierProvider((ref) {
  final cart = CartNotifier(
      allowOversell: () => ref.read(activeProfileProvider).valueOrNull?.allowOversell ?? false);
  ref.listen(authProvider, (_, __) => cart.clear());
  return cart;
});

// ── Today's total (minor units) ────────────────────────
final todayTotalProvider = FutureProvider<int>((ref) async {
  final profile = ref.watch(activeProfileProvider).valueOrNull;
  if (profile == null) return 0;
  return ref.read(saleDaoProvider).getTodayTotalMinor(profile.id);
});

// ── Recent sales ───────────────────────────────────────
final recentSalesProvider = FutureProvider<List<Sale>>((ref) async {
  final profile = ref.watch(activeProfileProvider).valueOrNull;
  if (profile == null) return [];
  return ref.read(saleDaoProvider).getByProfile(profile.id, limit: 50);
});

// ── Checkout logic ─────────────────────────────────────
/// Call as `ref.read(checkoutProvider)()`. Throws if the sale can't be saved
/// (e.g. `SaleRejectedException` when stock ran out); the cart is left intact
/// in that case.
final checkoutProvider =
    Provider<Future<void> Function()>((ref) => () => _checkout(ref));

Future<void> _checkout(Ref ref) async {
  final cart = ref.read(cartProvider);
  final profile = ref.read(activeProfileProvider).valueOrNull;
  if (profile == null || cart.items.isEmpty || cart.isCheckingOut) return;

  cart._setCheckingOut(true);
  try {
    await _recordCart(ref, cart, profile.id);
  } finally {
    cart._setCheckingOut(false);
    // Refresh stock on success, and on failure too so the POS shows what
    // is actually left.
    invalidateProductViews(ref.invalidate);
  }
}

Future<void> _recordCart(Ref ref, CartNotifier cart, String profileId) async {
  const uuid = Uuid();
  final saleId = uuid.v4();
  final now = DateTime.now();

  final sale = Sale(
    id: saleId,
    profileId: profileId,
    createdAt: now,
    subtotalMinor: cart.subtotalMinor,
    taxAmountMinor: 0, // Phase 2 will add tax calculation
    discountMinor: cart.discountMinor,
    totalMinor: cart.totalMinor,
    paymentMethod: cart.paymentMethod,
  );

  final saleItems = cart.items.map((ci) {
    return SaleItem(
      id: uuid.v4(),
      saleId: saleId,
      profileId: profileId,
      productId: ci.product.id,
      productName: ci.displayName,
      variantId: ci.variant?.id,
      qty: ci.qty,
      unitPriceMinor: ci.unitPriceMinor,
      costPriceMinor: ci.product.costPriceMinor,
    );
  }).toList();

  await ref.read(saleDaoProvider).recordSale(sale, saleItems);

  cart.clear();
  ref.invalidate(todayTotalProvider);
  ref.invalidate(recentSalesProvider);
}
