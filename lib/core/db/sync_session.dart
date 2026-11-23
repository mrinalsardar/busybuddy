import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database_helper.dart';
import 'supabase_connector.dart';

/// Syncs the local database with Supabase while a session exists, and stops
/// syncing when it ends. Local data and queued uploads stay, so a revoked
/// session loses nothing: signing in again resumes the upload. Only the user's
/// own sign-out clears them, through [clearLocalData].
///
/// The app never waits for this: it works on the local database, and local
/// changes queue for upload until the device is signed in and online.
class SyncSession {
  SyncSession(SupabaseClient client, this._connector) {
    // Emits initialSession first, so a stored session connects at startup.
    client.auth.onAuthStateChange.listen((state) {
      _enqueue(() async {
        if (state.session != null && !_connected) {
          _connected = true;
          await DatabaseHelper().connect(_connector);
        } else if (state.event == AuthChangeEvent.signedOut) {
          _connected = false;
          await DatabaseHelper().disconnect();
        }
      });
    });
  }

  final SupabaseConnector _connector;
  var _connected = false;
  // Steps run one after another, so a sign-in right after a sign-out connects
  // only once syncing has stopped and the data is cleared.
  var _queue = Future<void>.value();

  /// Completes when every step queued so far has finished.
  Future<void> get idle => _queue;

  /// Stops syncing and deletes the local data, after the steps queued so far.
  Future<void> clearLocalData() => _enqueue(() async {
        _connected = false;
        await DatabaseHelper().disconnectAndClear();
      });

  Future<void> _enqueue(Future<void> Function() step) {
    final done = _queue.then((_) async {
      try {
        await step();
      } catch (e) {
        _connected = false;
        debugPrint('Sync connection failed: $e');
      }
    });
    _queue = done;
    return done;
  }
}
