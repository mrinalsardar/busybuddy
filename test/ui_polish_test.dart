import 'package:busybuddy/core/models/models.dart';
import 'package:busybuddy/core/providers/core_providers.dart';
import 'package:busybuddy/core/utils/plural.dart';
import 'package:busybuddy/features/inventory/providers/inventory_providers.dart';
import 'package:busybuddy/features/inventory/screens/product_list_screen.dart';
import 'package:busybuddy/features/sales/providers/sales_providers.dart';
import 'package:busybuddy/features/sales/screens/pos_screen.dart';
import 'package:busybuddy/core/utils/money.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _shop = BusinessProfile(id: 'shop-1', name: 'Shop', type: BusinessType.general);

class _FakeProfile extends StateNotifier<AsyncValue<BusinessProfile?>>
    implements ActiveProfileNotifier {
  _FakeProfile() : super(const AsyncValue.data(_shop));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Product _product(String id, {int priceMinor = 1000}) =>
    Product(id: id, profileId: 'shop-1', name: 'Item $id', priceMinor: priceMinor, stockQty: 50);

void main() {
  test('countLabel uses the singular for one', () {
    expect(countLabel(0, 'item'), '0 items');
    expect(countLabel(1, 'item'), '1 item');
    expect(countLabel(2, 'item'), '2 items');
    expect(countLabel(2, 'box', 'boxes'), '2 boxes');
  });

  group('inventory empty states', () {
    Future<void> pump(WidgetTester tester, {String search = '', String? category}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeProfileProvider.overrideWith((ref) => _FakeProfile()),
          isOwnerProvider.overrideWithValue(true),
          productListProvider.overrideWith((ref) async => <Product>[]),
          avgSellingPriceProvider.overrideWith((ref) async => <String, int>{}),
          inventorySearchProvider.overrideWith((ref) => search),
          inventoryCategoryFilterProvider.overrideWith((ref) => category),
        ],
        child: const MaterialApp(home: ProductListScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no products and no search shows the first-run state', (tester) async {
      await pump(tester);
      expect(find.text('No products yet'), findsOneWidget);
      expect(find.text('No matching products'), findsNothing);
    });

    testWidgets('no match for a search says nothing matched and clears it', (tester) async {
      await pump(tester, search: 'zzz');
      expect(find.text('No matching products'), findsOneWidget);
      expect(find.text('No products yet'), findsNothing);
      expect(find.text('Add your first product to get started'), findsNothing);

      await tester.tap(find.text('Clear search and filter'));
      await tester.pumpAndSettle();
      expect(find.text('No products yet'), findsOneWidget);
    });

    testWidgets('no match for a category filter says nothing matched', (tester) async {
      await pump(tester, category: 'Shoes');
      expect(find.text('No matching products'), findsOneWidget);
    });
  });

  group('cart panel', () {
    Future<void> pump(WidgetTester tester, CartNotifier cart) async {
      tester.view.physicalSize = const Size(900 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeProfileProvider.overrideWith((ref) => _FakeProfile()),
          cartProvider.overrideWith((ref) => cart),
          posProductListProvider.overrideWith((ref) async => <Product>[]),
          todayTotalProvider.overrideWith((ref) async => 0),
        ],
        child: const MaterialApp(home: PosScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('one item reads "1 item", two read "2 items"', (tester) async {
      final cart = CartNotifier()..addItem(_product('a'));
      await pump(tester, cart);
      expect(find.text('1 item'), findsOneWidget);

      cart.addItem(_product('b'));
      await tester.pumpAndSettle();
      expect(find.text('2 items'), findsOneWidget);
    });

    testWidgets('a large line total stays on one line', (tester) async {
      final cart = CartNotifier()..addItem(_product('a', priceMinor: 19999998));
      await pump(tester, cart);
      final total = find.text(MoneyFormat.fallback.format(19999998));
      expect(total, findsWidgets);
      // The test font is far wider than a real one, so check the line's rules
      // (no wrapping, no clipping to a fixed width), not its pixel width.
      final lineTotals = tester.widgetList<Text>(total).where((t) => t.style?.fontSize == 14);
      expect(lineTotals, hasLength(1));
      for (final t in lineTotals) {
        expect(t.softWrap, false);
        expect(t.maxLines, 1);
      }
      // Both texts are one line: height under 1.5 lines of their font size.
      for (final e in total.evaluate()) {
        final fontSize = (e.widget as Text).style!.fontSize!;
        expect((e.renderObject! as RenderBox).size.height, lessThan(fontSize * 1.5));
      }
    });
  });
}
