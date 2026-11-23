import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/sync_session.dart';

/// A sign-in or shop-membership call failed. [message] is fit to show the user.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => message;
}

/// The account and shop-membership calls the UI makes to the backend.
///
/// [SupabaseAuthRepository] is the real one. [LocalAuthRepository] stands in
/// when no backend is configured, so the app runs on the local database only.
abstract class AuthRepository {
  /// False when the app runs without a backend: no sign-in, no sync.
  bool get enabled;

  /// Id of the signed-in user, or null when signed out.
  String? get userId;

  String? get email;

  /// The user id after every auth event: null once signed out.
  Stream<String?> get userChanges;

  /// Emails a one-time code to [email]. Creates the account on first use.
  Future<void> sendOtp(String email);

  /// Signs in with the code that [sendOtp] emailed.
  Future<void> verifyOtp(String email, String code);

  Future<void> signOut();

  /// Owner only: a single-use invite code for the shop [profileId].
  Future<String> createInvite(String profileId);

  /// Joins the shop that [code] belongs to as staff. Returns its profile id.
  Future<String> joinShop(String code);
}

class LocalAuthRepository implements AuthRepository {
  const LocalAuthRepository();

  @override
  bool get enabled => false;
  @override
  String? get userId => null;
  @override
  String? get email => null;
  @override
  Stream<String?> get userChanges => const Stream.empty();

  static Never _unsupported() => throw UnsupportedError('No backend is configured');

  @override
  Future<void> sendOtp(String email) async => _unsupported();
  @override
  Future<void> verifyOtp(String email, String code) async => _unsupported();
  @override
  Future<void> signOut() async => _unsupported();
  @override
  Future<String> createInvite(String profileId) async => _unsupported();
  @override
  Future<String> joinShop(String code) async => _unsupported();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client, {required this.clearLocalData});

  final SupabaseClient client;

  /// Deletes the local copy of the shop's data; see [SyncSession.clearLocalData].
  final Future<void> Function() clearLocalData;

  @override
  bool get enabled => true;

  @override
  String? get userId => client.auth.currentUser?.id;

  @override
  String? get email => client.auth.currentUser?.email;

  @override
  Stream<String?> get userChanges =>
      client.auth.onAuthStateChange.map((state) => state.session?.user.id);

  @override
  Future<void> sendOtp(String email) =>
      _run(() => client.auth.signInWithOtp(email: email, shouldCreateUser: true));

  @override
  Future<void> verifyOtp(String email, String code) =>
      _run(() => client.auth.verifyOTP(email: email, token: code, type: OtpType.email));

  /// Signs out. The session is removed on the device before the server is
  /// told, so a failed server call (offline) still signs out. Then the local
  /// copy is cleared so the next user never sees this shop's data. Callers
  /// confirm pending uploads first.
  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      if (client.auth.currentSession != null) {
        throw const AuthFailure('Could not sign out. Check your connection.');
      }
    }
    await clearLocalData();
  }

  @override
  Future<String> createInvite(String profileId) => _run(() async {
        final code = await client.rpc('create_invite', params: {'profile_id': profileId});
        return code as String;
      });

  @override
  Future<String> joinShop(String code) => _run(() async {
        final id = await client.rpc('join_shop', params: {'code': code});
        return id as String;
      });

  /// Runs [call], turning backend errors into an [AuthFailure].
  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on PostgrestException catch (e) {
      throw AuthFailure(switch (e.code) {
        '22023' => 'That invite code is not valid. It may be used or expired.',
        '42501' => 'You are not allowed to do that. Sign in again.',
        _ => e.message,
      });
    } catch (_) {
      throw const AuthFailure('Could not reach the server. Check your connection.');
    }
  }
}
