import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database_helper.dart';
import 'local_owner.dart';
import 'supabase_connector.dart';

/// A different account signed in while the previous account's changes are
/// still waiting to upload. The app stays out of reach until the user decides.
class OwnerConflict {
  const OwnerConflict({this.previousEmail});

  /// Email of the account that owns the unsynced changes, when known.
  final String? previousEmail;
}

/// Syncs the local database with Supabase while a session exists, and stops
/// syncing when it ends. Local data and queued uploads stay, so a revoked
/// session loses nothing: signing in again resumes the upload. Only the user's
/// own sign-out clears them, through [clearLocalData].
///
/// The local data belongs to one account (see [LocalOwner]). When another
/// account signs in, an empty upload queue means the old data is cleared and
/// the new account starts fresh. A queue with unsynced changes is never
/// discarded silently: syncing stays off and [conflict] is set until the user
/// calls [discardPendingChanges] or [leaveForPreviousAccount].
///
/// The app never waits for this: it works on the local database, and local
/// changes queue for upload until the device is signed in and online.
class SyncSession {
  SyncSession(this._client, SupabaseConnector connector, {Future<void> Function()? connectDatabase})
      : _connectDatabase = connectDatabase ?? (() => DatabaseHelper().connect(connector)) {
    // Emits initialSession first, so a stored session connects at startup.
    _client.auth.onAuthStateChange.listen((state) {
      _enqueue(() => _apply(state.session)).catchError((Object _) {});
    });
  }

  final SupabaseClient _client;
  final Future<void> Function() _connectDatabase;
  var _connected = false;
  // Steps run one after another, so a sign-in right after a sign-out connects
  // only once syncing has stopped and the data is cleared.
  var _queue = Future<void>.value();

  OwnerConflict? _conflict;
  final _conflicts = StreamController<OwnerConflict?>.broadcast();
  final _users = StreamController<String?>.broadcast();

  /// Set while the signed-in account cannot use the app, see the class docs.
  OwnerConflict? get conflict => _conflict;

  /// [conflict] after every change.
  Stream<OwnerConflict?> get conflictChanges => _conflicts.stream;

  /// The usable account after every auth event, once its data was checked:
  /// null when signed out or blocked by a [conflict].
  Stream<String?> get userChanges => _users.stream;

  /// Completes when every step queued so far has finished.
  Future<void> get idle => _queue;

  /// Checks the stored session. Call once at startup, before the first
  /// screen, so a pending [conflict] is known before anything is shown.
  Future<void> init() => _enqueue(() => _apply(_client.auth.currentSession));

  /// Stops syncing and deletes the local data, after the steps queued so far.
  /// Throws if the data could not be deleted.
  Future<void> clearLocalData() => _enqueue(() async {
        _connected = false;
        _setConflict(null);
        await DatabaseHelper().disconnectAndClear();
      });

  /// Drops the previous account's unsynced changes and local data, and
  /// continues with the signed-in account.
  Future<void> discardPendingChanges() => _enqueue(() async {
        final user = _client.auth.currentUser;
        if (user == null) throw StateError('Not signed in');
        await _startFresh(user);
      });

  /// Signs the new account out and keeps the local data and its queue, so the
  /// previous account can sign in again and upload them.
  Future<void> leaveForPreviousAccount() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      if (_client.auth.currentSession != null) rethrow;
    }
    await _enqueue(() async => _setConflict(null));
  }

  Future<void> _apply(Session? session) async {
    final user = session?.user;
    if (user == null) {
      _connected = false;
      _setConflict(null);
      await DatabaseHelper().disconnect();
      _users.add(null);
      return;
    }
    final db = await DatabaseHelper().database;
    final owner = await LocalOwner.read(db);
    if (owner == null || owner.userId == user.id) {
      if (owner == null || owner.email != user.email) await LocalOwner.write(db, user.id, user.email);
    } else if (!await LocalOwner.hasPendingUploads(db)) {
      await _startFresh(user);
      return;
    } else {
      _connected = false;
      await DatabaseHelper().disconnect();
      _setConflict(OwnerConflict(previousEmail: owner.email));
      _users.add(null);
      return;
    }
    _setConflict(null);
    await _connect();
    _users.add(user.id);
  }

  /// Replaces the local data with an empty copy owned by [user].
  Future<void> _startFresh(User user) async {
    _connected = false;
    await DatabaseHelper().disconnectAndClear();
    await LocalOwner.write(await DatabaseHelper().database, user.id, user.email);
    _setConflict(null);
    await _connect();
    _users.add(user.id);
  }

  Future<void> _connect() async {
    if (_connected) return;
    _connected = true;
    await _connectDatabase();
  }

  void _setConflict(OwnerConflict? conflict) {
    if (identical(conflict, _conflict) || (conflict == null && _conflict == null)) return;
    _conflict = conflict;
    _conflicts.add(conflict);
  }

  Future<void> _enqueue(Future<void> Function() step) {
    final result = _queue.then((_) => step());
    _queue = result.catchError((Object e) {
      _connected = false;
      debugPrint('Sync step failed: $e');
    });
    return result;
  }
}
