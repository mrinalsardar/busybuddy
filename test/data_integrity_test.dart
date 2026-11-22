import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:busybuddy/core/dao/daos.dart';
import 'package:busybuddy/core/db/database_helper.dart';
import 'package:busybuddy/core/models/models.dart';
import 'package:busybuddy/core/providers/core_providers.dart';
import 'package:busybuddy/core/router/app_router.dart';
import 'package:busybuddy/features/inventory/providers/inventory_providers.dart';
import 'package:busybuddy/features/sales/providers/sales_providers.dart';

const profile = BusinessProfile(id: 'profile-1', name: 'Shop', type: BusinessType.shoes);
// Has one variant; its stored stock becomes the variant total (5), not 10.
const product = Product(id: 'product-1', profileId: 'profile-1', name: 'Sneaker', priceMinor: 10000, stockQty: 10);
const variant = ProductVariant(id: 'variant-1', productId: 'product-1', size: '42', stockQty: 5);
// No variants.
const plain = Product(
    id: 'product-2', profileId: 'profile-1', name: 'Laces', priceMinor: 9999, costPriceMinor: 6000, stockQty: 10);

Future<Database> get db => DatabaseHelper().database;

Future<void> sell(Product p, {String? variantId, int qty = 1, String saleId = 'sale-1', DateTime? at}) =>
    SaleDao().recordSale(
      Sale(id: saleId, profileId: profile.id, createdAt: at ?? DateTime.now(), totalMinor: qty * p.priceMinor),
      [
        SaleItem(
          id: '$saleId-item',
          saleId: saleId,
          productId: p.id,
          productName: p.name,
          variantId: variantId,
          qty: qty,
          unitPriceMinor: p.priceMinor,
        ),
      ],
    );

Future<int> stockOf(String productId) async => (await ProductDao().getById(productId))!.stockQty;
Future<int> variantStock() async => (await ProductVariantDao().getById(variant.id))!.stockQty;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper().close();
    await DatabaseHelper().deleteDb();
    await BusinessProfileDao().insert(profile);
    await ProductDao().saveWithVariants(product, isNew: true, variants: [variant]);
    await ProductDao().saveWithVariants(plain, isNew: true);
  });

  tearDown(() => DatabaseHelper().close());

  group('product delete (F-01)', () {
    test('hard delete of a sold product is blocked, sale items survive', () async {
      await sell(product, variantId: variant.id);

      await expectLater(ProductDao().delete(product.id), throwsA(isA<DatabaseException>()));
      expect(await SaleItemDao().getBySale('sale-1'), hasLength(1));
    });

    test('archive hides product from lists but keeps sale history', () async {
      await sell(product, variantId: variant.id);

      await ProductDao().archive(product.id);

      final ids = (await ProductDao().getByProfile(profile.id)).map((p) => p.id);
      expect(ids, [plain.id]);
      expect(await ProductDao().getLowStock(profile.id), isEmpty);
      final items = await SaleItemDao().getBySale('sale-1');
      expect(items.single.productName, 'Sneaker');
    });

    test('deleting a profile still cascades through sales and products', () async {
      await sell(product, variantId: variant.id);

      await BusinessProfileDao().delete(profile.id);

      for (final table in ['product', 'product_variant', 'sale', 'sale_item']) {
        expect(await (await db).query(table), isEmpty, reason: table);
      }
    });
  });

  group('insert never replaces (F-03)', () {
    test('inserting an existing id throws and leaves child rows intact', () async {
      await sell(product, variantId: variant.id);

      await expectLater(BusinessProfileDao().insert(profile), throwsA(isA<DatabaseException>()));
      expect(await ProductDao().getByProfile(profile.id), hasLength(2));
      expect(await SaleItemDao().getBySale('sale-1'), hasLength(1));
    });

    test('editing a product keeps sale items linked to their variant', () async {
      await sell(product, variantId: variant.id);

      await ProductDao().saveWithVariants(
        product.copyWith(name: 'Sneaker v2'),
        isNew: false,
        variants: [variant.copyWith(stockQty: 9)],
      );

      final item = (await SaleItemDao().getBySale('sale-1')).single;
      expect(item.variantId, variant.id);
      expect(await variantStock(), 9);
    });
  });

  group('transactional product save (F-08)', () {
    test('variants removed from the form are deleted, new ones inserted', () async {
      const added = ProductVariant(id: 'variant-2', productId: 'product-1', size: '43');

      await ProductDao().saveWithVariants(product, isNew: false, variants: [added]);

      final ids = (await ProductVariantDao().getByProduct(product.id)).map((v) => v.id);
      expect(ids, ['variant-2']);
    });

    test('failed product write rolls back variant writes', () async {
      const added = ProductVariant(id: 'variant-2', productId: 'product-1', size: '43');

      // isNew with an existing id -> product insert fails inside the transaction.
      await expectLater(
        ProductDao().saveWithVariants(product, isNew: true, variants: [added]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await ProductVariantDao().getById('variant-2'), isNull);
    });
  });

  group('stock (F-05, F-06)', () {
    test('a product with variants stores the variant total as its stock', () async {
      expect(await stockOf(product.id), 5);

      await ProductDao().saveWithVariants(product, isNew: false, variants: [
        variant.copyWith(stockQty: 2),
        const ProductVariant(id: 'variant-2', productId: 'product-1', size: '43', stockQty: 4),
      ]);

      expect(await stockOf(product.id), 6);
    });

    test('selling a variant decrements variant and product stock', () async {
      await sell(product, variantId: variant.id, qty: 2);

      expect(await variantStock(), 3);
      expect(await stockOf(product.id), 3);
    });

    test('overselling is rejected and nothing is written', () async {
      await expectLater(sell(product, variantId: variant.id, qty: 6), throwsA(isA<SaleRejectedException>()));
      await expectLater(sell(plain, qty: 11), throwsA(isA<SaleRejectedException>()));

      expect(await SaleDao().getByProfile(profile.id), isEmpty);
      expect(await variantStock(), 5);
      expect(await stockOf(product.id), 5);
      expect(await stockOf(plain.id), 10);
    });

    test('selling a variant product without picking a variant is rejected', () async {
      await expectLater(sell(product), throwsA(isA<SaleRejectedException>()));
      expect(await SaleDao().getByProfile(profile.id), isEmpty);
    });

    test('with oversells allowed, a sale takes stock negative', () async {
      await BusinessProfileDao().update(profile.copyWith(allowOversell: true), profile.id);

      await sell(product, variantId: variant.id, qty: 7);

      expect(await variantStock(), -2);
      expect(await stockOf(product.id), -2);
      // A variant is still required.
      await expectLater(sell(product, saleId: 'sale-2'), throwsA(isA<SaleRejectedException>()));
    });

    test('with oversells allowed, the cart can go above stock', () {
      final cart = CartNotifier(allowOversell: () => true);
      for (var i = 0; i < 11; i++) {
        expect(cart.addItem(plain), isTrue);
      }
      expect(cart.updateQty(plain.id, 20), isTrue);
      expect(cart.addItem(plain.copyWith(id: 'none', stockQty: 0)), isTrue);
    });

    test('cart will not go above the stock on hand', () {
      final cart = CartNotifier();
      for (var i = 0; i < 10; i++) {
        expect(cart.addItem(plain), isTrue);
      }
      expect(cart.addItem(plain), isFalse);
      expect(cart.updateQty(plain.id, 11), isFalse);
      expect(cart.items.single.qty, 10);
      expect(cart.addItem(plain.copyWith(id: 'none', stockQty: 0)), isFalse);
    });
  });

  group('schema rules (F-13, F-18)', () {
    test('negative prices are rejected by the database', () async {
      await expectLater(
          ProductDao().insert(plain.copyWith(id: 'neg-price', priceMinor: -1)), throwsA(isA<DatabaseException>()));
      await expectLater(
          ProductDao().insert(plain.copyWith(id: 'neg-cost', costPriceMinor: -1)), throwsA(isA<DatabaseException>()));
    });

    test('barcode is unique per profile among active products', () async {
      await ProductDao().insert(plain.copyWith(id: 'a', barcode: '890'));

      await expectLater(
          ProductDao().insert(plain.copyWith(id: 'b', barcode: '890')), throwsA(isA<DatabaseException>()));

      await ProductDao().archive('a');
      await ProductDao().insert(plain.copyWith(id: 'b', barcode: '890'));
    });

    test("today's total counts today only, in minor units", () async {
      await sell(plain, saleId: 'today');
      await sell(plain, saleId: 'yesterday', at: DateTime.now().subtract(const Duration(days: 1)));

      expect(await SaleDao().getTodayTotalMinor(profile.id), 9999);
    });

    test("a customer's total spent is calculated from their sales", () async {
      const customer = Customer(id: 'c1', profileId: 'profile-1', name: 'Asha');
      await CustomerDao().insert(customer);
      await sell(plain, saleId: 's1');
      await sell(plain, saleId: 's2');
      await sell(plain, saleId: 's3');
      await (await db).update('sale', {'customer_id': 'c1'}, where: "id IN ('s1', 's2')");

      expect(await CustomerDao().getTotalSpentMinor('c1'), 2 * 9999);
    });

    test('timestamps are stored as UTC', () async {
      await sell(plain);
      final row = (await (await db).query('sale')).single;
      expect(row['created_at'] as String, endsWith('Z'));
    });
  });

  group('checkout (F-02, F-07)', () {
    late ProviderContainer container;

    setUp(() async {
      container = ProviderContainer();
      container.read(activeProfileProvider);
      while (container.read(activeProfileProvider).isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    tearDown(() => container.dispose());

    test('two overlapping checkouts record a single sale', () async {
      container.read(cartProvider).addItem(plain);
      final checkout = container.read(checkoutProvider);

      await Future.wait([checkout(), checkout()]);

      expect(await SaleDao().getByProfile(profile.id), hasLength(1));
      expect(await stockOf(plain.id), 9);
      expect(container.read(cartProvider).items, isEmpty);
      expect(container.read(cartProvider).isCheckingOut, isFalse);
    });

    test('sale item stores the product name, price and cost', () async {
      container.read(cartProvider).addItem(plain);

      await container.read(checkoutProvider)();

      final sale = (await SaleDao().getByProfile(profile.id)).single;
      final item = (await SaleItemDao().getBySale(sale.id)).single;
      expect(item.productName, 'Laces');
      expect(item.unitPriceMinor, 9999);
      expect(item.costPriceMinor, 6000);
    });

    test('sale records the price set at the counter, not the suggested price', () async {
      final cart = container.read(cartProvider)..addItem(plain)..addItem(plain);
      cart.updatePrice(plain.id, 8500);
      expect(cart.subtotalMinor, 17000);

      await container.read(checkoutProvider)();

      final sale = (await SaleDao().getByProfile(profile.id)).single;
      expect(sale.totalMinor, 17000);
      expect((await SaleItemDao().getBySale(sale.id)).single.unitPriceMinor, 8500);
      expect((await ProductDao().getById(plain.id))!.priceMinor, 9999);
    });

    test('average selling price is qty-weighted over past sales', () async {
      container.read(cartProvider)
        ..addItem(plain)
        ..addItem(plain)
        ..updatePrice(plain.id, 9000);
      await container.read(checkoutProvider)();
      container.read(cartProvider)
        ..addItem(plain)
        ..updatePrice(plain.id, 9901);
      await container.read(checkoutProvider)();

      final avg = await container.read(avgSellingPriceProvider.future);
      // (2 * 9000 + 9901) / 3 = 9300.33 -> 9300
      expect(avg[plain.id], 9300);
      expect(avg.containsKey(product.id), isFalse);
    });

    test('currency can change only while there are no products or sales', () async {
      final notifier = container.read(activeProfileProvider.notifier);
      final current = container.read(activeProfileProvider).value!;

      await expectLater(
          notifier.updateProfile(current.copyWith(currencyDecimals: 3)), throwsA(isA<StateError>()));
      // Other settings still save.
      await notifier.updateProfile(current.copyWith(allowOversell: true));
      expect((await BusinessProfileDao().getById(profile.id))!.allowOversell, isTrue);

      await BusinessProfileDao().delete(profile.id);
      const empty = BusinessProfile(id: 'p2', name: 'New', type: BusinessType.general);
      await notifier.setProfile(empty);
      await notifier.updateProfile(empty.copyWith(currency: 'KWD', currencyDecimals: 3));
      expect((await BusinessProfileDao().getById('p2'))!.currencyDecimals, 3);
    });

    test('the router is built once, not rebuilt on profile changes (F-15)', () async {
      final router = container.read(routerProvider);
      final current = container.read(activeProfileProvider).value!;

      await container.read(activeProfileProvider.notifier).updateProfile(current.copyWith(allowOversell: true));

      expect(container.read(routerProvider), same(router));
    });

    test('POS list ignores the inventory search and shows stock after a sale', () async {
      container.read(inventorySearchProvider.notifier).state = 'no match';
      expect(await container.read(productListProvider.future), isEmpty);

      container.read(cartProvider).addItem(plain);
      await container.read(checkoutProvider)();

      final pos = await container.read(posProductListProvider.future);
      expect(pos.firstWhere((p) => p.id == plain.id).stockQty, 9);
    });
  });
}
