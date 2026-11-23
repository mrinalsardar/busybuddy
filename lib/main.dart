import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth/auth_repository.dart';
import 'core/db/database_helper.dart';
import 'core/db/supabase_connector.dart';
import 'core/providers/core_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

// Backend config, passed with --dart-define (never commit real values):
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
//     --dart-define=POWERSYNC_URL=...
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

  // Dark status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.surfaceCard,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // The router needs to know before the first frame whether a stored session
  // exists. Initializing reads it from the device, so it works offline.
  final auth = await _initAuth();
  runApp(ProviderScope(
    overrides: [if (auth != null) authRepositoryProvider.overrideWithValue(auth)],
    child: const BusyBuddyApp(),
  ));
}

/// Starts Supabase Auth and syncing when a backend is configured. Returns
/// null when it is not, or cannot start: the app then runs on the local
/// database only, without sign-in.
Future<AuthRepository?> _initAuth() async {
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty || _powerSyncUrl.isEmpty) return null;
  try {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
  } catch (e) {
    debugPrint('Backend not started, running locally: $e');
    return null;
  }
  final client = Supabase.instance.client;
  _syncWithSession(client, SupabaseConnector(client, powerSyncUrl: _powerSyncUrl));
  return SupabaseAuthRepository(client);
}

/// Syncs the local database with Supabase while a session exists, and removes
/// stops syncing when the session ends. Local data and queued uploads stay, so
/// a revoked session loses nothing: signing in again resumes the upload. Only
/// the user's own sign-out clears them ([SupabaseAuthRepository.signOut]).
/// The app never waits for this:
/// it works on the local database, and local changes queue for upload until
/// the device is signed in and online.
void _syncWithSession(SupabaseClient client, SupabaseConnector connector) {
  var connected = false;
  // Steps run one after another, so a sign-in right after a sign-out connects
  // only once syncing has stopped.
  var queue = Future<void>.value();
  // Emits initialSession first, so a stored session connects at startup.
  client.auth.onAuthStateChange.listen((state) {
    queue = queue.then((_) async {
      try {
        if (state.session != null && !connected) {
          connected = true;
          await DatabaseHelper().connect(connector);
        } else if (state.event == AuthChangeEvent.signedOut) {
          connected = false;
          await DatabaseHelper().disconnect();
        }
      } catch (e) {
        connected = false;
        debugPrint('Sync connection failed: $e');
      }
    });
  });
}

class BusyBuddyApp extends ConsumerWidget {
  const BusyBuddyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'BusyBuddy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
