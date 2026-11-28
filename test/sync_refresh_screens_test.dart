import 'dart:async';
import 'dart:typed_data';

import 'package:busybuddy/core/dao/daos.dart';
import 'package:busybuddy/core/db/database_helper.dart';
import 'package:busybuddy/core/images/image_providers.dart';
import 'package:busybuddy/core/images/product_image_store.dart';
import 'package:busybuddy/core/models/models.dart';
import 'package:busybuddy/core/providers/core_providers.dart';
import 'package:busybuddy/core/theme/app_theme.dart';
import 'package:busybuddy/features/inventory/providers/inventory_providers.dart';
import 'package:busybuddy/features/inventory/screens/product_form_screen.dart';
import 'package:busybuddy/features/inventory/screens/product_list_screen.dart';
import 'package:busybuddy/features/sales/providers/sales_providers.dart';
import 'package:busybuddy/features/sales/screens/pos_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import 'test_db.dart';

const _shop = BusinessProfile(
    id: 'shop-1', name: 'Shop', type: BusinessType.shoes, variantSupport: true);

class _FakeProfile extends StateNotifier<AsyncValue<BusinessProfile?>>
    implements ActiveProfileNotifier {
  _FakeProfile(BusinessProfile shop) : super(AsyncValue.data(shop));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lets the database's real I/O and the widgets' fake timers both progress.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<T> _db<T>(WidgetTester tester, Future<T> Function() action) async =>
    (await tester.runAsync(action)) as T;

/// Writes straight to the database, as a sync does: no provider is told.
Future<void> _synced(WidgetTester tester, String sql) async {
  await tester.runAsync(() async => (await DatabaseHelper().database).execute(sql));
  await _settle(tester);
}

/// A picture store whose save stays pending until the test ends it.
class _SlowImageStore implements ProductImageStore {
  final pending = Completer<String>();

  @override
  Future<String> save(String profileId, String productId, Uint8List jpeg) => pending.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedPicker implements ProductImagePicker {
  _FixedPicker(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List?> pick(ImagePickSource source) async => bytes;
}

Future<void> _pump(WidgetTester tester, Widget screen,
    {BusinessProfile shop = _shop, List<Override> overrides = const []}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...overrides,
      activeProfileProvider.overrideWith((ref) => _FakeProfile(shop)),
      isOwnerProvider.overrideWithValue(true),
    ],
    // Saving the product form navigates to /inventory.
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => screen),
        GoRoute(path: '/inventory', builder: (_, _) => const SizedBox()),
      ]),
    ),
  ));
  await _settle(tester);
}

/// The text of the form field with [hint].
String _text(WidgetTester tester, String hint) => tester
    .widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == hint))
    .controller!
    .text;

Finder _fieldWith(String hint) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

/// A widget test that unmounts the screen and lets its database work finish:
/// work left in the test's fake-async zone would block closing the database.
void _screenTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });
}

void main() {
  useTestDatabase(close: false);

  Future<void> addProduct(WidgetTester tester, String id, String name, {int stock = 10}) =>
      tester.runAsync(() => ProductDao()
          .insert(Product(id: id, profileId: 'shop-1', name: name, priceMinor: 500, stockQty: stock)));

  List<String> column(WidgetTester tester, String hint) => [
        for (final f in tester.widgetList<TextField>(_fieldWith(hint))) f.controller!.text,
      ];

  _screenTest('Inventory keeps its scroll position and search through a synced change',
      (tester) async {
    for (var i = 10; i < 40; i++) {
      await addProduct(tester, 'p$i', 'Item $i');
    }
    await _pump(tester, const ProductListScreen());
    await tester.enterText(find.byType(TextField), 'Item');
    await _settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await _settle(tester);
    ScrollPosition position() => tester
        .state<ScrollableState>(find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)))
        .position;
    final offset = position().pixels;
    expect(offset, greaterThan(0));

    await tester.runAsync(() async => (await DatabaseHelper().database)
        .execute("UPDATE product SET name = 'Item renamed ' || id"));
    // No frame of the reload may replace the list with a spinner.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    expect(find.textContaining('Item renamed'), findsWidgets);
    expect(position().pixels, offset);
    expect(_text(tester, 'Search products…'), 'Item');
  });

  _screenTest('an open edit form takes synced changes into untouched fields only', (tester) async {
    await addProduct(tester, 'p1', 'Old name');
    await _pump(tester, const ProductFormScreen(productId: 'p1'));
    expect(_text(tester, 'Product Name'), 'Old name');
    await tester.enterText(_fieldWith('SKU'), 'TYPED');

    await _synced(tester,
        "UPDATE product SET name = 'New name', sku = 'SYNCED', category = 'Bags', "
        "price_minor = 900, stock_qty = 7 WHERE id = 'p1'");

    expect(_text(tester, 'Product Name'), 'New name');
    expect(_text(tester, 'Category'), 'Bags');
    expect(_text(tester, 'Suggested Price'), '9.00');
    expect(_text(tester, 'Quantity'), '7');
    expect(_text(tester, 'SKU'), 'TYPED');
  });

  _screenTest('saving a form open through a sync keeps the synced values', (tester) async {
    await addProduct(tester, 'p1', 'Old name');
    await _pump(tester, const ProductFormScreen(productId: 'p1'),
        shop: const BusinessProfile(id: 'shop-1', name: 'Shop', type: BusinessType.general));
    await tester.enterText(_fieldWith('SKU'), 'TYPED');
    await _synced(tester, "UPDATE product SET name = 'New name', stock_qty = 7 WHERE id = 'p1'");

    await tester.ensureVisible(find.text('Update Product'));
    await tester.pump();
    await tester.tap(find.text('Update Product'));
    await _settle(tester);

    final saved = await _db(tester, () => ProductDao().getById('p1'));
    expect(saved!.name, 'New name');
    expect(saved.sku, 'TYPED');
    expect(saved.stockQty, 7);
    final corrections = await _db(
        tester,
        () async => (await DatabaseHelper().database)
            .getAll("SELECT * FROM stock_movement WHERE reason = 'correction'"));
    expect(corrections, isEmpty);
  });

  _screenTest('an open edit form follows synced variants and keeps edited ones', (tester) async {
    await addProduct(tester, 'p1', 'Shoe', stock: 0);
    await tester.runAsync(() async {
      for (final (id, size) in [('v1', '40'), ('v2', '41'), ('v3', '42')]) {
        await ProductVariantDao().insert(
            ProductVariant(id: id, productId: 'p1', profileId: 'shop-1', size: size, stockQty: 2));
      }
    });
    await _pump(tester, const ProductFormScreen(productId: 'p1'));
    // The user changes the first variant's size and removes the third.
    await tester.enterText(_fieldWith('Size').first, '39');
    final third = find.byIcon(Icons.remove_circle_outline).at(2);
    await tester.ensureVisible(third);
    await tester.tap(third);
    await tester.pump();

    await _synced(tester, "UPDATE product_variant SET size = 'X', stock_qty = 9 WHERE id = 'v1'");
    await _synced(tester, "DELETE FROM product_variant WHERE id = 'v2'");
    await _synced(tester,
        "INSERT INTO product_variant (id, product_id, profile_id, size, stock_qty) "
        "VALUES ('v4', 'p1', 'shop-1', '44', 4)");

    expect(column(tester, 'Size'), ['39', '44']);
    expect(column(tester, 'Qty'), ['9', '4']);
  });

  Future<void> addVariants(WidgetTester tester, List<(String, String)> sizes) =>
      tester.runAsync(() async {
        for (final (id, size) in sizes) {
          await ProductVariantDao().insert(ProductVariant(
              id: id, productId: 'p1', profileId: 'shop-1', size: size, stockQty: 2));
        }
      });

  Future<void> tapUpdate(WidgetTester tester) async {
    // A snack bar would cover the button.
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await tester.pump();
    await tester.ensureVisible(find.text('Update Product'));
    await tester.pump();
    await tester.tap(find.text('Update Product'));
    await _settle(tester);
    // A successful save also runs the route transition.
    await _settle(tester);
  }

  _screenTest('a variant deleted by sync leaves the form even if edited, and Save keeps it deleted',
      (tester) async {
    await addProduct(tester, 'p1', 'Shoe', stock: 0);
    await addVariants(tester, [('v1', '40'), ('v2', '41')]);
    await _pump(tester, const ProductFormScreen(productId: 'p1'));
    await tester.enterText(_fieldWith('Size').at(1), '43');
    Future<int> v2Movements() => _db(
        tester,
        () async => (await (await DatabaseHelper().database)
                .getAll("SELECT * FROM stock_movement WHERE variant_id = 'v2'"))
            .length);
    final movementsBefore = await v2Movements();

    await _synced(tester, "DELETE FROM product_variant WHERE id = 'v2'");

    expect(column(tester, 'Size'), ['40']);
    expect(find.text('A variant you edited was deleted elsewhere and removed'), findsOneWidget);
    await tapUpdate(tester);
    expect(find.byType(ProductFormScreen), findsNothing);
    final stored = await _db(tester, () => ProductVariantDao().getByProduct('p1'));
    expect(stored.map((v) => v.id), ['v1']);
    expect(await v2Movements(), movementsBefore);
  });

  _screenTest('a variant that a sync removes and brings back returns to the form', (tester) async {
    await addProduct(tester, 'p1', 'Shoe', stock: 0);
    await addVariants(tester, [('v1', '40'), ('v2', '41')]);
    await _pump(tester, const ProductFormScreen(productId: 'p1'));
    await _synced(tester, "DELETE FROM product_variant WHERE id = 'v2'");
    expect(column(tester, 'Size'), ['40']);
    expect(find.byType(SnackBar), findsNothing);

    await _synced(tester,
        "INSERT INTO product_variant (id, product_id, profile_id, size, stock_qty) "
        "VALUES ('v2', 'p1', 'shop-1', '41', 2)");

    expect(column(tester, 'Size'), ['40', '41']);
    await tapUpdate(tester);
    expect(find.byType(ProductFormScreen), findsNothing);
    final stored = await _db(tester, () => ProductVariantDao().getByProduct('p1'));
    expect(stored.map((v) => v.id), unorderedEquals(['v1', 'v2']));
  });

  for (final pictureFails in [true, false]) {
    _screenTest(
        'values synced while the picture saves are kept when it '
        '${pictureFails ? 'fails and Save is retried' : 'succeeds'}', (tester) async {
      await addProduct(tester, 'p1', 'Old name');
      final store = _SlowImageStore();
      final picture = img.encodeJpg(img.Image(width: 8, height: 8));
      await _pump(tester, const ProductFormScreen(productId: 'p1'),
          shop: const BusinessProfile(id: 'shop-1', name: 'Shop', type: BusinessType.general),
          overrides: [
            productImageStoreProvider.overrideWithValue(store),
            productImagePickerProvider.overrideWithValue(_FixedPicker(picture)),
          ]);
      await tester.tap(find.text('Gallery'));
      await _settle(tester);
      await tapUpdate(tester);

      await _synced(tester, "UPDATE product SET name = 'New name', stock_qty = 7 WHERE id = 'p1'");
      if (pictureFails) {
        store.pending.completeError(StateError('disk full'));
        await _settle(tester);
        await tester.ensureVisible(find.text('Remove'));
        await tester.pump();
        await tester.tap(find.text('Remove'));
        await tester.pump();
        await tapUpdate(tester);
      } else {
        store.pending.complete('shop-1/p1/new.jpg');
        await _settle(tester);
        await _settle(tester);
      }

      expect(find.byType(ProductFormScreen), findsNothing);
      final saved = await _db(tester, () => ProductDao().getById('p1'));
      expect(saved!.name, 'New name');
      expect(saved.stockQty, 7);
      expect(saved.imagePath, pictureFails ? isNull : 'shop-1/p1/new.jpg');
    });
  }

  _screenTest('open cart lines limit quantity by the synced stock and keep the rest',
      (tester) async {
    await addProduct(tester, 'p1', 'Shoe', stock: 0);
    await addProduct(tester, 'p2', 'Belt', stock: 1);
    await addVariants(tester, [('v1', '40')]);
    await _pump(tester, const PosScreen());
    final cart = ProviderScope.containerOf(tester.element(find.byType(PosScreen))).read(cartProvider);
    await tester.tap(find.text('Belt'));
    await _settle(tester);
    await tester.tap(find.text('Shoe'));
    await _settle(tester);
    await tester.tap(find.text('40'));
    await _settle(tester);
    expect(cart.updateQty('p1_v1', 2), isTrue);
    expect(cart.updateQty('p1_v1', 3), isFalse);

    await _synced(tester, "UPDATE product_variant SET stock_qty = 8 WHERE id = 'v1'");
    await _synced(tester,
        "UPDATE product SET name = 'Strap', price_minor = 900, stock_qty = 3 WHERE id = 'p2'");

    await tester.tap(find.byIcon(Icons.add).at(1));
    await _settle(tester);
    await tester.tap(find.text('Strap'));
    await _settle(tester);
    expect([for (final i in cart.items) i.qty], [2, 3]);
    expect(cart.items.first.product.name, 'Belt');
    expect(cart.items.first.unitPriceMinor, 500);

    await _synced(tester, "UPDATE product_variant SET stock_qty = 1 WHERE id = 'v1'");
    expect(cart.items.last.qty, 3);
    await tester.tap(find.byIcon(Icons.add).at(1));
    await tester.pump();
    expect(find.text('Only 1 in stock'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove).at(1));
    await tester.pump();
    expect(cart.items.last.qty, 2);
  });

  _screenTest('the open variant picker shows synced stock, and the cart price is left alone',
      (tester) async {
    await addProduct(tester, 'p1', 'Shoe', stock: 0);
    await addProduct(tester, 'p2', 'Belt');
    await tester.runAsync(() => ProductVariantDao().insert(const ProductVariant(
        id: 'v1', productId: 'p1', profileId: 'shop-1', size: '40', stockQty: 2)));
    await _pump(tester, const PosScreen());
    final cart = ProviderScope.containerOf(tester.element(find.byType(PosScreen))).read(cartProvider);
    await tester.tap(find.text('Belt'));
    await _settle(tester);
    cart.updatePrice('p2', 123);
    await tester.tap(find.text('Shoe'));
    await _settle(tester);
    expect(find.text('2 in stock'), findsOneWidget);

    await _synced(tester, "UPDATE product_variant SET stock_qty = 8 WHERE id = 'v1'");
    await _synced(tester, "UPDATE product SET name = 'Boot', price_minor = 900 WHERE id = 'p1'");

    expect(find.text('8 in stock'), findsOneWidget);
    expect(cart.items.single.unitPriceMinor, 123);

    await tester.tap(find.text('40'));
    await _settle(tester);

    // The line added now starts from the synced product and stock.
    final added = cart.items.last;
    expect(added.product.name, 'Boot');
    expect(added.unitPriceMinor, 900);
    expect(added.available, 8);
    expect(cart.items.first.unitPriceMinor, 123);
  });

  _screenTest('an invalidated product list still refreshes after the screen reopens',
      (tester) async {
    await addProduct(tester, 'p1', 'Old name');
    await _pump(tester, const ProductListScreen());
    final container =
        ProviderScope.containerOf(tester.element(find.byType(ProductListScreen)));
    invalidateProductViews(container.invalidate);
    await _settle(tester);

    await _synced(tester, "UPDATE product SET name = 'New name'");

    expect(find.text('New name'), findsOneWidget);
  });
}
