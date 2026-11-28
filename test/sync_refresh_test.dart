
import 'package:busybuddy/core/dao/daos.dart';
import 'package:busybuddy/core/db/database_helper.dart';
import 'package:busybuddy/core/models/models.dart';
import 'package:busybuddy/core/providers/core_providers.dart';
import 'package:busybuddy/features/inventory/providers/inventory_providers.dart';
import 'package:busybuddy/features/sales/providers/sales_providers.dart';
import 'package:busybuddy/features/settings/providers/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

const _shop = BusinessProfile(id: 'shop-1', name: 'Shop', type: BusinessType.general);

/// Writes straight to the database, as a sync does: no provider is told.
Future<void> _synced(String sql, [List<Object?> args = const []]) async {
  await (await DatabaseHelper().database).execute(sql, args);
}

/// Waits until the latest value of [states] satisfies [test].
Future<void> _until<T>(List<AsyncValue<T>> states, bool Function(T value) test) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    final last = states.isEmpty ? null : states.last;
    if (last != null && !last.isLoading && last.hasValue && test(last.requireValue)) return;
    if (DateTime.now().isAfter(deadline)) fail('Provider did not update; last state: $last');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useTestDatabase();

  late ProviderContainer container;

  setUp(() async {
    await BusinessProfileDao().insert(_shop);
    await ProductDao().insert(const Product(id: 'p1', profileId: 'shop-1', name: 'Old name', stockQty: 10));
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  /// Every state [provider] goes through while watched, as an open screen
  /// watches it.
  List<AsyncValue<T>> watch<T>(ProviderListenable<AsyncValue<T>> provider) {
    final states = <AsyncValue<T>>[];
    container.listen(provider, (_, next) => states.add(next), fireImmediately: true);
    return states;
  }

  Future<void> loadProfile() => _until(watch(activeProfileProvider), (p) => p != null);

  test('a synced product rename reaches the open Inventory and POS lists', () async {
    await loadProfile();
    final inventory = watch(productListProvider);
    final pos = watch(posProductListProvider);
    await _until(inventory, (p) => p.single.name == 'Old name');
    await _until(pos, (p) => p.single.name == 'Old name');

    await _synced("UPDATE product SET name = 'New name' WHERE id = 'p1'");

    await _until(inventory, (p) => p.single.name == 'New name');
    await _until(pos, (p) => p.single.name == 'New name');
  });

  test('synced rows reach every other open view', () async {
    await loadProfile();
    final categories = watch(categoryListProvider);
    final product = watch(productByIdProvider('p1'));
    final variants = watch(variantsProvider('p1'));
    final lowStock = watch(lowStockCountProvider);
    final average = watch(avgSellingPriceProvider);
    final today = watch(todayTotalProvider);
    final sales = watch(recentSalesProvider);
    final items = watch(saleItemsProvider('s1'));
    final currency = watch(canEditCurrencyProvider);
    await _until(categories, (c) => c.isEmpty);
    await _until(product, (p) => p!.name == 'Old name');
    await _until(variants, (v) => v.isEmpty);
    await _until(lowStock, (n) => n == 0);
    await _until(average, (a) => a.isEmpty);
    await _until(today, (t) => t == 0);
    await _until(sales, (s) => s.isEmpty);
    await _until(items, (i) => i.isEmpty);
    await _until(currency, (c) => !c);

    await _synced("UPDATE product SET category = 'Bags', stock_qty = 1 WHERE id = 'p1'");
    await _until(categories, (c) => c.join() == 'Bags');
    await _until(product, (p) => p!.stockQty == 1);
    await _until(lowStock, (n) => n == 1);

    await _synced("INSERT INTO product_variant (id, product_id, profile_id, size, stock_qty) "
        "VALUES ('v1', 'p1', 'shop-1', 'M', 3)");
    await _until(variants, (v) => v.any((x) => x.size == 'M'));

    final now = DateTime.now().toUtc().toIso8601String();
    await _synced(
        "INSERT INTO sale (id, profile_id, created_at, subtotal_minor, tax_amount_minor, "
        "discount_minor, total_minor, payment_method) VALUES ('s1', 'shop-1', ?, 500, 0, 0, 500, 'cash')",
        [now]);
    await _until(today, (t) => t == 500);
    await _until(sales, (s) => s.any((x) => x.id == 's1'));

    await _synced("INSERT INTO sale_item (id, sale_id, profile_id, product_id, product_name, qty, "
        "unit_price_minor, cost_price_minor) VALUES ('i1', 's1', 'shop-1', 'p1', 'Old name', 1, 500, 0)");
    await _until(items, (i) => i.any((x) => x.id == 'i1'));
    await _until(average, (a) => a['p1'] == 500);
  });

  test('a synced first product locks the currency in open Settings', () async {
    await _synced('DELETE FROM product');
    await loadProfile();
    final currency = watch(canEditCurrencyProvider);
    await _until(currency, (c) => c);

    await _synced("INSERT INTO product (id, profile_id, name, archived) VALUES ('p2', 'shop-1', 'X', 0)");

    await _until(currency, (c) => !c);
  });

  test('a refresh from sync never drops back to a loading state', () async {
    await loadProfile();
    final inventory = watch(productListProvider);
    await _until(inventory, (p) => p.isNotEmpty);
    inventory.clear();

    await _synced("UPDATE product SET name = 'New name' WHERE id = 'p1'");
    await _until(inventory, (p) => p.single.name == 'New name');

    // What `AsyncValue.when` shows as a spinner: loading that is not a refresh.
    expect(inventory.where((s) => s.isLoading && !s.isRefreshing), isEmpty);
    expect(inventory.where((s) => !s.hasValue), isEmpty);
  });

  test('changed shop settings do not reload the product lists', () async {
    await loadProfile();
    final inventory = watch(productListProvider);
    final pos = watch(posProductListProvider);
    await _until(inventory, (p) => p.isNotEmpty);
    await _until(pos, (p) => p.isNotEmpty);
    inventory.clear();
    pos.clear();

    await _synced("UPDATE business_profile SET name = 'Renamed' WHERE id = 'shop-1'");
    await container.read(activeProfileProvider.notifier).reloadAfterSync();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(container.read(activeProfileProvider).value!.name, 'Renamed');
    expect(inventory, isEmpty);
    expect(pos, isEmpty);
  });

  test('a change to an unrelated table reloads nothing', () async {
    await loadProfile();
    final inventory = watch(productListProvider);
    final sales = watch(recentSalesProvider);
    await _until(inventory, (p) => p.isNotEmpty);
    await _until(sales, (s) => s.isEmpty);
    inventory.clear();
    sales.clear();

    await _synced("INSERT INTO supplier (id, profile_id, name) VALUES ('x', 'shop-1', 'S')");
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(inventory, isEmpty);
    expect(sales, isEmpty);
  });
}
