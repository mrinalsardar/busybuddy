import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/core_providers.dart';
import '../../features/profile/screens/profile_type_screen.dart';
import '../../features/profile/screens/business_details_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/inventory/screens/product_list_screen.dart';
import '../../features/inventory/screens/product_form_screen.dart';
import '../../features/sales/screens/pos_screen.dart';
import '../../features/sales/screens/sale_history_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Built once. Profile changes re-run [GoRouter.redirect] through
/// `refreshListenable` instead of rebuilding the router, which would reset
/// navigation (e.g. bounce out of Settings after changing a setting).
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(activeProfileProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final profileAsync = ref.read(activeProfileProvider);
      final profile = profileAsync.valueOrNull;
      final isLoading = profileAsync.isLoading;
      final currentPath = state.uri.path;

      if (isLoading) return null;

      // No profile → force onboarding
      if (profile == null) {
        if (!currentPath.startsWith('/onboarding')) {
          return '/onboarding';
        }
        return null;
      }

      // Profile exists → don't allow going back to onboarding
      if (currentPath.startsWith('/onboarding')) {
        return '/';
      }
      return null;
    },
    routes: [
      // ── Onboarding ───────────────────────────────
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const ProfileTypeScreen(),
        routes: [
          GoRoute(
            path: 'details/:type',
            builder: (_, state) {
              final type = state.pathParameters['type']!;
              return BusinessDetailsScreen(businessType: type);
            },
          ),
        ],
      ),

      // ── Main shell with bottom nav ───────────────
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, _) => const NoTransitionPage(
              child: PosScreen(),
            ),
          ),
          GoRoute(
            path: '/inventory',
            pageBuilder: (_, _) => const NoTransitionPage(
              child: ProductListScreen(),
            ),
            routes: [
              GoRoute(
                path: 'add',
                builder: (_, _) => const ProductFormScreen(),
              ),
              GoRoute(
                path: 'edit/:id',
                builder: (_, state) => ProductFormScreen(
                  productId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/sales',
            pageBuilder: (_, _) => const NoTransitionPage(
              child: SaleHistoryScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, _) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
