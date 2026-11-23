import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/db/database_helper.dart';
import 'core/db/supabase_connector.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

// Backend config, passed with --dart-define (never commit real values):
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
//     --dart-define=POWERSYNC_URL=...
// Without them the app runs on the local database only.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _powerSyncUrl = String.fromEnvironment('POWERSYNC_URL');

void main() {
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

  runApp(const ProviderScope(child: BusyBuddyApp()));
  unawaited(_startSync());
}

/// Syncs the local database with Supabase while a Supabase session exists.
/// The app never waits for this: it works on the local database, and local
/// changes queue for upload until the device is signed in and online.
Future<void> _startSync() async {
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty || _powerSyncUrl.isEmpty) return;
  try {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
    final client = Supabase.instance.client;
    final connector = SupabaseConnector(client, powerSyncUrl: _powerSyncUrl);
    var connected = false;
    // Emits initialSession first, so a stored session connects at startup.
    client.auth.onAuthStateChange.listen((state) async {
      try {
        if (state.session != null && !connected) {
          connected = true;
          await DatabaseHelper().connect(connector);
        } else if (state.event == AuthChangeEvent.signedOut && connected) {
          connected = false;
          await DatabaseHelper().disconnect();
        }
      } catch (e) {
        connected = false;
        debugPrint('Sync connection failed: $e');
      }
    });
  } catch (e) {
    debugPrint('Sync not started, running locally: $e');
  }
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
