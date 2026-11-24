import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/core_providers.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/owner_conflict_screen.dart';
import '../../features/auth/screens/syncing_screen.dart';
import '../../features/profile/screens/join_shop_screen.dart';
import '../../features/profile/screens/profile_type_screen.dart';
import '../../features/profile/screens/business_details_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/inventory/screens/product_list_screen.dart';
import '../../features/inventory/screens/product_form_screen.dart';
import '../../features/sales/screens/pos_screen.dart';
import '../../features/sales/screens/sale_history_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Built once. Profile and auth changes re-run [GoRouter.redirect] through
/// `refreshListenable` instead of rebuilding the router, which would reset
/// navigation (e.g. bounce out of Settings after changing a setting).
///
/// With a backend: another account's unsynced changes on the device hold the
/// app at /conflict; signed out goes to /login; signed in without a shop waits
/// at /syncing for the first sync, then goes to /onboarding (create a shop, or
/// join one at /onboarding/join). Without a backend there is no login or sync.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(activeProfileProvider, (_, _) => refresh.value++);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.listen(ownerConflictProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authEnabled = ref.read(authRepositoryProvider).enabled;
      final signedIn = ref.read(authProvider) != null;
      final profileAsync = ref.read(activeProfileProvider);
      final profile = profileAsync.valueOrNull;
      final currentPath = state.uri.path;
      bool on(String path) => currentPath == path || currentPath.startsWith('$path/');

      // Another account's unsynced changes are on this device: nothing else is
      // reachable until the user chooses what happens to them.
      if (ref.read(ownerConflictProvider) != null) {
        return on('/conflict') ? null : '/conflict';
      }
      if (on('/conflict')) return '/';

      if (authEnabled) {
        if (!signedIn) return on('/login') ? null : '/login';
        if (on('/login')) return '/';
      }

      if (profileAsync.isLoading) return null;

      if (profile == null) {
        // A new device has no shop until its first sync: don't offer to create
        // a second shop before the existing one had a chance to arrive.
        if (authEnabled && ref.read(syncStateProvider).valueOrNull?.hasSynced != true) {
          return on('/syncing') ? null : '/syncing';
        }
        return on('/onboarding') ? null : '/onboarding';
      }

      // Profile exists → don't allow going back to onboarding
      if (on('/onboarding') || on('/syncing')) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/conflict', builder: (_, _) => const OwnerConflictScreen()),
      GoRoute(path: '/syncing', builder: (_, _) => const SyncingScreen()),

      // ── Onboarding ───────────────────────────────
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const ProfileTypeScreen(),
        routes: [
          GoRoute(path: 'join', builder: (_, _) => const JoinShopScreen()),
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
