import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth/auth_repository.dart';
import 'core/db/database_helper.dart';
import 'core/db/supabase_connector.dart';
import 'core/images/image_providers.dart';
import 'core/images/product_image_store.dart';
import 'core/db/sync_session.dart';
import 'core/providers/core_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/router/app_router.dart';

// Backend config, passed at build time from a gitignored env/<env>.json (public
// values only; see env/example.json):
//   flutter run --flavor qa --dart-define-from-file=env/qa.json
// Without them the app runs on the local database only.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _powerSyncUrl = String.fromEnvironment('POWERSYNC_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait on mobile
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // The router needs to know before the first frame whether a stored session
  // exists. Initializing reads it from the device, so it works offline.
  final backend = await _initAuth();
  // Read before the first frame, so it already uses the saved theme.
  final preferences = await _loadPreferences();
  runApp(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(preferences),
      if (backend != null) ...[
        authRepositoryProvider.overrideWithValue(backend.auth),
        productImageStoreProvider.overrideWithValue(backend.images),
      ],
    ],
    child: const BusyBuddyApp(),
  ));
}

Future<SharedPreferences?> _loadPreferences() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('Device preferences unavailable: $e');
    return null;
  }
}

/// Starts Supabase Auth and syncing when a backend is configured. Returns
/// null when it is not, or cannot start: the app then runs on the local
/// database only, without sign-in.
Future<({AuthRepository auth, ProductImageStore images})?> _initAuth() async {
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty || _powerSyncUrl.isEmpty) return null;
  try {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
  } catch (e) {
    debugPrint('Backend not started, running locally: $e');
    return null;
  }
  final client = Supabase.instance.client;
  final images = ProductImageStore(client, directory: DatabaseHelper().productImageDir);
  final sync = SyncSession(client, SupabaseConnector(client, powerSyncUrl: _powerSyncUrl, images: images));
  // Decide before the first frame whether the stored session may use the
  // local data (see SyncSession).
  await sync.init();
  return (auth: SupabaseAuthRepository(client, sync: sync), images: images);
}

class BusyBuddyApp extends ConsumerWidget {
  const BusyBuddyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'BusyBuddy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ref.watch(themeModeProvider),
      // For screens without an app bar; app bars set the same style.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.overlayStyle(Theme.of(context).brightness),
        child: child!,
      ),
      routerConfig: router,
    );
  }
}
