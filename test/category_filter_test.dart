import 'dart:async';

import 'package:busybuddy/core/models/models.dart';
import 'package:busybuddy/core/providers/core_providers.dart';
import 'package:busybuddy/core/theme/app_theme.dart';
import 'package:busybuddy/features/inventory/providers/inventory_providers.dart';
import 'package:busybuddy/features/inventory/screens/product_list_screen.dart';
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

void main() {
  Future<void> pump(WidgetTester tester, Future<List<String>> Function() load) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeProfileProvider.overrideWith((ref) => _FakeProfile()),
        isOwnerProvider.overrideWithValue(true),
        productListProvider.overrideWith((ref) async => <Product>[]),
        avgSellingPriceProvider.overrideWith((ref) async => <String, int>{}),
        categoryListProvider.overrideWith((ref) => load()),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: const ProductListScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Filter by Category'), findsNothing);
  }

  testWidgets('the first tap opens the sheet with the categories', (tester) async {
    await pump(tester, () async => ['Shoes']);

    await openFilter(tester);

    expect(find.text('Filter by Category'), findsOneWidget);
    expect(find.text('Shoes'), findsOneWidget);
  });

  testWidgets('the first open after the categories change shows the new list', (tester) async {
    var categories = ['Shoes'];
    await pump(tester, () async => categories);
    await openFilter(tester);
    await closeSheet(tester);

    categories = ['Bags'];
    final container =
        ProviderScope.containerOf(tester.element(find.byType(ProductListScreen)));
    invalidateProductViews(container.invalidate);
    await tester.pumpAndSettle();
    await openFilter(tester);

    expect(find.text('Bags'), findsOneWidget);
    expect(find.text('Shoes'), findsNothing);
  });

  testWidgets('each open reloads, even without an invalidation', (tester) async {
    var categories = ['Shoes'];
    await pump(tester, () async => categories);
    await openFilter(tester);
    await closeSheet(tester);

    categories = ['Bags'];
    await openFilter(tester);

    expect(find.text('Bags'), findsOneWidget);
    expect(find.text('Shoes'), findsNothing);
  });

  testWidgets('an open sheet follows an invalidation', (tester) async {
    var categories = ['Shoes'];
    await pump(tester, () async => categories);
    await openFilter(tester);

    categories = ['Bags'];
    final container =
        ProviderScope.containerOf(tester.element(find.byType(ProductListScreen)));
    invalidateProductViews(container.invalidate);
    await tester.pumpAndSettle();

    expect(find.text('Bags'), findsOneWidget);
    expect(find.text('Shoes'), findsNothing);
  });

  testWidgets('the sheet opens while loading and fills in when done', (tester) async {
    final categories = Completer<List<String>>();
    await pump(tester, () => categories.future);

    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Filter by Category'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    categories.complete(['Shoes']);
    await tester.pumpAndSettle();

    expect(find.text('Shoes'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed load says so and can be retried', (tester) async {
    var fail = true;
    await pump(tester, () async {
      if (fail) throw Exception('boom');
      return ['Shoes'];
    });

    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text("Couldn't load categories"), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Shoes'), findsOneWidget);
    expect(find.text("Couldn't load categories"), findsNothing);
  });

  testWidgets('picking a category sets the filter and closes the sheet', (tester) async {
    await pump(tester, () async => ['Shoes']);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(ProductListScreen)));
    await openFilter(tester);

    await tester.tap(find.text('Shoes'));
    await tester.pumpAndSettle();

    expect(find.text('Filter by Category'), findsNothing);
    expect(container.read(inventoryCategoryFilterProvider), 'Shoes');

    await openFilter(tester);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('Filter by Category'), findsNothing);
    expect(container.read(inventoryCategoryFilterProvider), isNull);
  });
}
