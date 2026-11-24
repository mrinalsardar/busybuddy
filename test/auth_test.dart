import 'dart:async';

import 'package:busybuddy/core/auth/auth_repository.dart';
import 'package:busybuddy/core/dao/business_profile_dao.dart';
import 'package:busybuddy/core/db/database_helper.dart';
import 'package:busybuddy/core/db/local_owner.dart';
import 'package:busybuddy/core/db/sync_session.dart';
import 'package:busybuddy/core/models/models.dart';
import 'package:busybuddy/core/providers/core_providers.dart';
import 'package:busybuddy/features/auth/screens/login_screen.dart';
import 'package:busybuddy/features/auth/screens/syncing_screen.dart';
import 'package:busybuddy/features/profile/screens/join_shop_screen.dart';
import 'package:busybuddy/features/profile/screens/profile_type_screen.dart';
import 'package:busybuddy/features/settings/screens/settings_screen.dart';
import 'package:busybuddy/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

/// An auth backend in memory. Code `123456` signs in; `GOOD` joins a shop.
class FakeAuth implements AuthRepository {
  FakeAuth({this.enabled = true, String? user}) : _userId = user;

  @override
  final bool enabled;
  String? _userId;
  final _changes = StreamController<String?>.broadcast();
  final sentTo = <String>[];
  final joined = <String>[];
  var invites = 0;
  var signedOut = false;

  @override
  String? get userId => _userId;
  @override
  String? get email => _userId == null ? null : 'staff@example.com';
  @override
  Stream<String?> get userChanges => _changes.stream;

  @override
  Future<void> sendOtp(String email) async => sentTo.add(email);

  @override
  Future<void> verifyOtp(String email, String code) async {
    if (code != '123456') throw const AuthFailure('Token has expired or is invalid');
    _userId = 'user-1';
    _changes.add(_userId);
  }

  @override
  OwnerConflict? get conflict => null;
  @override
  Stream<OwnerConflict?> get conflictChanges => const Stream.empty();
  @override
  Future<void> discardPendingChanges() async {}
  @override
  Future<void> leaveForPreviousAccount() async {}

  @override
  Future<void> signOut() async {
    signedOut = true;
    _userId = null;
    _changes.add(null);
  }

  @override
  Future<String> createInvite(String profileId) async {
    invites++;
    return 'ABCD234567';
  }

  @override
  Future<String> joinShop(String code) async {
    if (code != 'GOOD') throw const AuthFailure('That invite code is not valid.');
    joined.add(code);
    return 'shop-1';
  }
}

/// A profile DAO that answers from memory, so widget tests need no database.
class FakeProfileDao extends BusinessProfileDao {
  BusinessProfile? profile;
  String? role;

  @override
  Future<BusinessProfile?> getActiveProfile({String? userId}) async => profile;
  @override
  Future<String?> getMemberRole(String profileId, String userId) async => role;
  @override
  Future<bool> hasProductsOrSales(String profileId) async => true;
}

const shop = BusinessProfile(id: 'shop-1', name: 'Shop', type: BusinessType.general);

void main() {
  group('active shop', () {
    useTestDatabase();
    final dao = BusinessProfileDao();

    Future<void> addShop(String id, String createdAt) async => (await DatabaseHelper().database)
        .execute(
            "INSERT INTO business_profile (id, name, type, created_at) VALUES (?, 'S', 'general', ?)",
            [id, createdAt]);

    Future<void> addMember(String profileId, String userId, String role, String createdAt) async =>
        (await DatabaseHelper().database).execute(
            'INSERT INTO shop_member (id, profile_id, user_id, role, created_at) VALUES (?, ?, ?, ?, ?)',
            ['$profileId:$userId', profileId, userId, role, createdAt]);

    test('is the shop the user is a member of', () async {
      await addShop('a', '2026-01-01T00:00:00.000Z');
      await addShop('b', '2026-01-02T00:00:00.000Z');
      await addMember('b', 'user-1', 'staff', '2026-01-03T00:00:00.000Z');
      expect((await dao.getActiveProfile(userId: 'user-1'))?.id, 'b');
    });

    test('is the earliest membership when the user has several', () async {
      await addShop('a', '2026-01-01T00:00:00.000Z');
      await addShop('b', '2026-01-02T00:00:00.000Z');
      await addMember('b', 'user-1', 'owner', '2026-01-03T00:00:00.000Z');
      await addMember('a', 'user-1', 'staff', '2026-01-04T00:00:00.000Z');
      expect((await dao.getActiveProfile(userId: 'user-1'))?.id, 'b');
    });

    Future<void> own(String userId) async => LocalOwner.write(await DatabaseHelper().database, userId, null);

    test('falls back to the local shop of the account that owns the data', () async {
      await addShop('a', '2026-01-01T00:00:00.000Z');
      await own('user-1');
      expect((await dao.getActiveProfile(userId: 'user-1'))?.id, 'a');
      expect((await dao.getActiveProfile())?.id, 'a');
    });

    test('never falls back to the shop of another account', () async {
      await addShop('a', '2026-01-01T00:00:00.000Z');
      await own('user-1');
      expect(await dao.getActiveProfile(userId: 'user-2'), isNull);
    });

    test('does not fall back while nobody owns the data', () async {
      await addShop('a', '2026-01-01T00:00:00.000Z');
      expect(await dao.getActiveProfile(userId: 'user-1'), isNull);
    });

    test('is null without any shop', () async {
      expect(await dao.getActiveProfile(userId: 'user-1'), isNull);
    });

    test('member role comes from shop_member', () async {
      await addShop('a', '2026-01-01T00:00:00.000Z');
      await addMember('a', 'user-1', 'staff', '2026-01-03T00:00:00.000Z');
      expect(await dao.getMemberRole('a', 'user-1'), 'staff');
      expect(await dao.getMemberRole('a', 'user-2'), isNull);
    });
  });

  group('screens', () {
    late FakeAuth auth;
    late FakeProfileDao dao;
    late StreamController<SyncState> status;

    setUp(() {
      auth = FakeAuth();
      dao = FakeProfileDao();
      status = StreamController<SyncState>();
    });
    tearDown(() => status.close());

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          businessProfileDaoProvider.overrideWithValue(dao),
          syncStateProvider.overrideWith((_) => status.stream),
        ],
        child: const BusyBuddyApp(),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> settle(WidgetTester tester) async {
      // Long enough to finish a page transition.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('signed out shows the login screen', (tester) async {
      await pumpApp(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('sign-in with an emailed code leads to the first sync', (tester) async {
      await pumpApp(tester);
      await tester.enterText(find.byKey(const Key('email')), 'staff@example.com');
      await tester.tap(find.text('Send code'));
      await settle(tester);
      expect(auth.sentTo, ['staff@example.com']);

      await tester.enterText(find.byKey(const Key('code')), '000000');
      await tester.tap(find.text('Verify'));
      await settle(tester);
      expect(find.text('Token has expired or is invalid'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.enterText(find.byKey(const Key('code')), '123456');
      await tester.tap(find.text('Verify'));
      await settle(tester);
      // Signed in, no shop on this device, first sync not done.
      expect(find.byType(SyncingScreen), findsOneWidget);
    });

    testWidgets('a rejected email format is not sent', (tester) async {
      await pumpApp(tester);
      await tester.enterText(find.byKey(const Key('email')), 'nope');
      await tester.tap(find.text('Send code'));
      await settle(tester);
      expect(auth.sentTo, isEmpty);
      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('after the first sync without a shop the user can create or join one',
        (tester) async {
      auth = FakeAuth(user: 'user-1');
      await pumpApp(tester);
      status.add(const SyncState());
      await settle(tester);
      expect(find.byType(SyncingScreen), findsOneWidget);

      status.add(SyncState(lastSyncedAt: DateTime(2026, 1, 1)));
      await settle(tester);
      expect(find.byType(ProfileTypeScreen), findsOneWidget);
      expect(find.text('Have an invite code?'), findsOneWidget);
    });

    testWidgets('the first sync can bring the shop, which skips onboarding', (tester) async {
      auth = FakeAuth(user: 'user-1');
      await pumpApp(tester);
      status.add(const SyncState());
      await settle(tester);
      expect(find.byType(SyncingScreen), findsOneWidget);

      dao.profile = shop;
      status.add(SyncState(lastSyncedAt: DateTime(2026, 1, 1)));
      await settle(tester);
      expect(find.byType(SyncingScreen), findsNothing);
      expect(find.byType(ProfileTypeScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('an invite code joins a shop; a bad code shows the error', (tester) async {
      auth = FakeAuth(user: 'user-1');
      await pumpApp(tester);
      status.add(SyncState(lastSyncedAt: DateTime(2026, 1, 1)));
      await settle(tester);

      await tester.tap(find.text('Have an invite code?'));
      await settle(tester);
      expect(find.byType(JoinShopScreen), findsOneWidget);

      await tester.enterText(find.byKey(const Key('inviteCode')), 'BAD');
      await tester.tap(find.text('Join shop'));
      await settle(tester);
      expect(find.text('That invite code is not valid.'), findsOneWidget);
      expect(auth.joined, isEmpty);

      await tester.enterText(find.byKey(const Key('inviteCode')), 'GOOD');
      await tester.tap(find.text('Join shop'));
      await settle(tester);
      expect(auth.joined, ['GOOD']);
      expect(find.text('You joined the shop'), findsOneWidget);

      // The next sync delivers the shop, and the router leaves the screen.
      dao.profile = shop;
      status.add(SyncState(lastSyncedAt: DateTime(2026, 1, 2)));
      await settle(tester);
      expect(find.byType(JoinShopScreen), findsNothing);
    });

    testWidgets('without a backend there is no login or invite option', (tester) async {
      auth = FakeAuth(enabled: false);
      await pumpApp(tester);
      await settle(tester);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(ProfileTypeScreen), findsOneWidget);
      expect(find.text('Have an invite code?'), findsNothing);
    });

    Future<void> pumpSettings(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          businessProfileDaoProvider.overrideWithValue(dao),
          syncStateProvider.overrideWith((_) => status.stream),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await settle(tester);
    }

    testWidgets('the owner can change shop settings and invite staff', (tester) async {
      auth = FakeAuth(user: 'user-1');
      dao
        ..profile = shop
        ..role = 'owner';
      await pumpSettings(tester);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);

      await tester.tap(find.text('Invite staff'));
      await settle(tester);
      expect(auth.invites, 1);
      expect(find.text('ABCD234567'), findsOneWidget);
    });

    testWidgets('staff see shop settings read-only and cannot invite', (tester) async {
      auth = FakeAuth(user: 'user-1');
      dao
        ..profile = shop
        ..role = 'staff';
      await pumpSettings(tester);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
      expect(find.text('Invite staff'), findsNothing);
      expect(find.text('Only the shop owner can change these settings.'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });
}
