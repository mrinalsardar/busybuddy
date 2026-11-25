import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:busybuddy/core/dao/daos.dart';
import 'package:busybuddy/core/models/models.dart';
import 'package:busybuddy/core/theme/app_theme.dart';
import 'package:busybuddy/features/inventory/screens/product_form_screen.dart';

import 'package:busybuddy/core/providers/core_providers.dart';

const profile = BusinessProfile(id: 'profile-1', name: 'Shop', type: BusinessType.general);
const product = Product(id: 'product-1', profileId: 'profile-1', name: 'Laces', priceMinor: 100);

// Fake DAO: no database, so the widget test runs in fake-async time.
class FakeProductDao extends ProductDao {
  final archived = <String>[];
  @override
  Future<Product?> getById(String id) async => product;
  @override
  Future<void> archive(String productId) async => archived.add(productId);
}

class FakeProfileDao extends BusinessProfileDao {
  @override
  Future<BusinessProfile?> getActiveProfile({String? userId}) async => profile;
}

// The form sits in a ShellRoute like in the app: showDialog uses the root
// navigator, so a pop with the page's context would remove the page instead.
late FakeProductDao dao;

Widget app() {
  dao = FakeProductDao();
  final router = GoRouter(
    initialLocation: '/inventory/product-1',
    routes: [
      ShellRoute(
        builder: (_, _, child) => Scaffold(body: child),
        routes: [
          GoRoute(path: '/inventory', builder: (_, _) => const Text('Inventory list')),
          GoRoute(
            path: '/inventory/:id',
            builder: (_, s) => ProductFormScreen(productId: s.pathParameters['id']),
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      productDaoProvider.overrideWithValue(dao),
      businessProfileDaoProvider.overrideWithValue(FakeProfileDao()),
    ],
    child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
  );
}

void main() {
  Future<void> openDialog(WidgetTester t) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.delete_outline_rounded));
    await t.pumpAndSettle();
    expect(find.text('Delete Product?'), findsOneWidget);
  }

  testWidgets('Cancel closes the dialog and keeps the edit page', (t) async {
    await openDialog(t);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Delete Product?'), findsNothing);
    expect(find.text('Edit Product'), findsOneWidget);
    expect(dao.archived, isEmpty);
  });

  testWidgets('Delete archives the product, closes the dialog, shows Inventory', (t) async {
    await openDialog(t);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.text('Delete Product?'), findsNothing);
    expect(find.text('Inventory list'), findsOneWidget);
    expect(dao.archived, ['product-1']);
  });
}
