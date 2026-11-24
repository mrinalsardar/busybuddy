import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:busybuddy/core/auth/auth_repository.dart';
import 'package:busybuddy/core/dao/daos.dart';
import 'package:busybuddy/core/db/database_helper.dart';
import 'package:busybuddy/core/db/supabase_connector.dart';
import 'package:busybuddy/core/db/local_owner.dart';
import 'package:busybuddy/core/db/sync_session.dart';
import 'package:busybuddy/core/models/models.dart';

import 'test_db.dart';

const profile = BusinessProfile(id: 'profile-1', name: 'Shop', type: BusinessType.shoes);
const plain = Product(id: 'product-1', profileId: 'profile-1', name: 'Laces', priceMinor: 9999, stockQty: 10);
const shoe = Product(id: 'product-2', profileId: 'profile-1', name: 'Sneaker', priceMinor: 5000);
const variant = ProductVariant(id: 'variant-1', productId: 'product-2', profileId: 'profile-1', size: '42', stockQty: 5);

/// One request the connector sent to the fake Supabase server.
class Sent {
  final String method;
  final String path;
  final Map<String, String> query;
  final String prefer;
  final Object? body;
  Sent(http.Request r)
      : method = r.method,
        path = r.url.path.replaceFirst('/rest/v1/', ''),
        query = r.url.queryParameters,
        prefer = r.headers['Prefer'] ?? r.headers['prefer'] ?? '',
        body = r.body.isEmpty ? null : jsonDecode(r.body);

  @override
  String toString() => '$method $path $query $body';
}

/// A Supabase server that records requests. [reply] can return an error
/// (or throw, for a network error); null means success.
class FakeSupabase {
  final sent = <Sent>[];
  ({String code, int status})? Function(Sent request) reply = (_) => null;

  late final client = SupabaseClient(
    'http://supabase.test',
    'anon-key',
    httpClient: MockClient((request) async {
      final s = Sent(request);
      sent.add(s);
      final error = reply(s);
      if (error != null) {
        return http.Response(jsonEncode({'code': error.code, 'message': 'rejected ${error.code}'}), error.status,
            request: request, headers: {'content-type': 'application/json'});
      }
      return http.Response(s.path.startsWith('rpc/') ? '{}' : '', 200, request: request);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  List<Sent> to(String path) => sent.where((s) => s.path == path).toList();
}

/// A signed-in session whose token does not expire during the test.
Future<void> signIn(SupabaseClient client) async {
  String b64(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  const userId = '00000000-0000-0000-0000-000000000001';
  final token = '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': userId, 'exp': exp, 'role': 'authenticated'})}.sig';
  await client.auth.setInitialSession(jsonEncode({
    'access_token': token,
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': exp,
    'refresh_token': 'refresh',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'app_metadata': <String, Object>{},
      'user_metadata': <String, Object>{},
      'created_at': '2026-11-01T00:00:00Z',
    },
  }));
}

Future<void> sell(Product p, {String saleId = 'sale-1', String? variantId, int qty = 1}) => SaleDao().recordSale(
      Sale(id: saleId, profileId: profile.id, createdAt: DateTime.now(), totalMinor: qty * p.priceMinor),
      [
        SaleItem(
          id: '$saleId-item',
          saleId: saleId,
          profileId: profile.id,
          productId: p.id,
          productName: p.name,
          variantId: variantId,
          qty: qty,
          unitPriceMinor: p.priceMinor,
        ),
      ],
    );

void main() {
  useTestDatabase();

  late FakeSupabase server;
  late SupabaseConnector connector;

  Future<void> upload() async => connector.uploadData(await DatabaseHelper().database);
  Future<bool> queueEmpty() async => await (await DatabaseHelper().database).getNextCrudTransaction() == null;

  setUp(() async {
    server = FakeSupabase();
    connector = SupabaseConnector(server.client, powerSyncUrl: 'http://powersync.test');
    await signIn(server.client);
    await BusinessProfileDao().insert(profile);
    await ProductDao().insert(plain);
    await ProductDao().saveWithVariants(shoe, isNew: true, variants: [variant]);
  });

  test('credentials come from the Supabase session', () async {
    final credentials = (await connector.fetchCredentials())!;
    expect(credentials.endpoint, 'http://powersync.test');
    expect(credentials.userId, '00000000-0000-0000-0000-000000000001');

    final signedOut = SupabaseConnector(FakeSupabase().client, powerSyncUrl: 'http://powersync.test');
    expect(await signedOut.fetchCredentials(), isNull);
  });

  test('a new shop uploads through create_shop, without local-only columns', () async {
    await upload();

    final call = server.to('rpc/create_shop').single;
    final sent = (call.body as Map)['profile'] as Map;
    expect(sent['id'], profile.id);
    expect(sent['type'], 'shoes');
    expect(sent.containsKey('google_account_id'), isFalse);
    expect(server.to('business_profile'), isEmpty);
  });

  test('a sale uploads as one record_sale call, with no separate stock upload', () async {
    await upload();
    server.sent.clear();

    await sell(plain, qty: 2);
    await sell(shoe, saleId: 'sale-2', variantId: variant.id);
    await upload();

    expect(server.sent.map((s) => s.path), ['rpc/record_sale', 'rpc/record_sale']);
    final body = server.sent.first.body as Map;
    expect((body['sale'] as Map)['id'], 'sale-1');
    expect((body['sale'] as Map)['profile_id'], profile.id);
    final items = body['items'] as List;
    expect(items.single['id'], 'sale-1-item');
    expect(items.single['qty'], 2);
    expect(items.single['product_id'], plain.id);
    expect(await queueEmpty(), isTrue);
  });

  test('stock movements upload as inserts that ignore an existing id', () async {
    await upload();

    final inserts = server.to('stock_movement');
    expect(inserts.map((s) => ((s.body as Map)['product_id'], (s.body as Map)['delta'])), [
      (plain.id, 10),
      (shoe.id, 5),
    ]);
    for (final s in inserts) {
      expect(s.method, 'POST');
      expect(s.prefer, contains('resolution=ignore-duplicates'));
      expect(s.query['on_conflict'], 'id');
      expect((s.body as Map).containsKey('created_by'), isFalse);
    }
    // A product uploads before its opening stock.
    final paths = server.sent.map((s) => s.path).toList();
    expect(paths.indexOf('product'), lessThan(paths.indexOf('stock_movement')));
  });

  test('stock_qty is never uploaded', () async {
    await sell(plain, qty: 2);
    await ProductDao().updateStock(plain.id, 20);
    await ProductDao().saveWithVariants(shoe.copyWith(name: 'Sneaker 2'), isNew: false,
        variants: [variant.copyWith(stockQty: 9)]);
    await upload();

    for (final s in server.sent) {
      expect(jsonEncode(s.body), isNot(contains('stock_qty')), reason: '$s');
    }
    // The stock-only changes left nothing to send for the product rows
    // beyond their inserts and the rename.
    expect(server.to('product').map((s) => s.method), ['POST', 'POST', 'PATCH']);
    expect(server.to('stock_movement'), hasLength(4));
    expect(await queueEmpty(), isTrue);
  });

  test('a permanent error is recorded and does not block later changes', () async {
    await upload();
    server.sent.clear();
    await sell(plain, saleId: 'bad');
    await sell(plain, saleId: 'good');
    server.reply = (s) => s.path == 'rpc/record_sale' && ((s.body as Map)['sale'] as Map)['id'] == 'bad'
        ? (code: '23503', status: 409)
        : null;

    await upload();

    expect(server.to('rpc/record_sale').map((s) => ((s.body as Map)['sale'] as Map)['id']), ['bad', 'good']);
    expect(await queueEmpty(), isTrue);
    final errors = await (await DatabaseHelper().database).getAll('SELECT * FROM upload_error ORDER BY table_name');
    expect(errors.map((e) => (e['table_name'], e['row_id'], e['code'])), [
      ('sale', 'bad', '23503'),
      ('sale_item', 'bad-item', '23503'),
    ]);
  });

  test('a network or server error keeps the change queued for a retry', () async {
    server.reply = (s) => s.path == 'rpc/create_shop' ? throw http.ClientException('offline') : null;
    await expectLater(upload(), throwsA(isA<http.ClientException>()));
    expect(await queueEmpty(), isFalse);

    server.reply = (s) => s.path == 'rpc/create_shop' ? (code: '57014', status: 500) : null;
    await expectLater(upload(), throwsA(isA<PostgrestException>()));
    expect(await queueEmpty(), isFalse);

    server.reply = (_) => null;
    await upload();
    expect(await queueEmpty(), isTrue);
    expect(await (await DatabaseHelper().database).getAll('SELECT * FROM upload_error'), isEmpty);
  });

  test('without a session nothing uploads and the queue is kept', () async {
    await server.client.auth.signOut();

    await expectLater(upload(), throwsStateError);
    expect(server.to('rpc/create_shop'), isEmpty);
    expect(await queueEmpty(), isFalse);
  });

  test('a session ending on its own keeps local data and queued uploads', () async {
    final sync = SyncSession(server.client, connector);
    await server.client.auth.signOut();
    await Future<void>.delayed(Duration.zero);
    await sync.idle;

    expect(await ProductDao().getById('product-1'), isNotNull);
    expect(await queueEmpty(), isFalse);
  });

  test('signing out clears local data and queued uploads', () async {
    final sync = SyncSession(server.client, connector);
    await SupabaseAuthRepository(server.client, sync: sync).signOut();

    expect(await ProductDao().getById('product-1'), isNull);
    expect(await queueEmpty(), isTrue);
  });

  test('signing out throws when the local data could not be cleared', () async {
    final repo = SupabaseAuthRepository(server.client,
        sync: SyncSession(server.client, connector), clearLocalData: () async => throw StateError('disk'));
    await expectLater(repo.signOut(), throwsA(isA<AuthFailure>()));
  });

  group('another account signs in on the same device', () {
    const owner = '00000000-0000-0000-0000-000000000001';
    var connects = 0;

    Future<SyncSession> session() async {
      connects = 0;
      final sync = SyncSession(server.client, connector, connectDatabase: () async => connects++);
      await sync.init();
      return sync;
    }

    Future<void> signInAs(String userId, String email) async {
      String b64(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final token = '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': userId, 'exp': exp, 'role': 'authenticated'})}.sig';
      await server.client.auth.setInitialSession(jsonEncode({
        'access_token': token,
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': exp,
        'refresh_token': 'refresh',
        'user': {
          'id': userId,
          'email': email,
          'aud': 'authenticated',
          'app_metadata': <String, Object>{},
          'user_metadata': <String, Object>{},
          'created_at': '2026-11-01T00:00:00Z',
        },
      }));
    }

    Future<String?> storedOwner() async => (await LocalOwner.read(await DatabaseHelper().database))?.userId;

    test('the first sign-in claims the data and connects', () async {
      final sync = await session();
      await sync.idle;
      expect(await storedOwner(), owner);
      expect(sync.conflict, isNull);
      expect(connects, 1);
    });

    test('the same account keeps its data and queue', () async {
      final sync = await session();
      await sync.init();
      expect(sync.conflict, isNull);
      expect(await ProductDao().getById('product-1'), isNotNull);
      expect(await queueEmpty(), isFalse);
    });

    test('an empty queue clears the old data for the new account', () async {
      final sync = await session();
      await upload();
      expect(await queueEmpty(), isTrue);

      await signInAs('user-2', 'two@example.com');
      await sync.init();

      expect(sync.conflict, isNull);
      expect(await ProductDao().getById('product-1'), isNull);
      expect(await BusinessProfileDao().getActiveProfile(userId: 'user-2'), isNull);
      expect(await storedOwner(), 'user-2');
      expect(connects, 2);
    });

    test('unsynced changes block the new account and are kept', () async {
      final sync = await session();
      await BusinessProfileDao().getActiveProfile(userId: owner);
      await signInAs('user-2', 'two@example.com');
      await sync.init();

      expect(sync.conflict, isNotNull);
      expect(await storedOwner(), owner);
      expect(await ProductDao().getById('product-1'), isNotNull);
      expect(await queueEmpty(), isFalse);
      expect(connects, 1);
      // The new account never sees the previous account's shop.
      expect(await BusinessProfileDao().getActiveProfile(userId: 'user-2'), isNull);
    });

    test('queued changes never upload under another account', () async {
      final sync = await session();
      await signInAs('user-2', 'two@example.com');
      await sync.init();

      await expectLater(upload(), throwsStateError);
      expect(server.sent, isEmpty);
      expect(await queueEmpty(), isFalse);
    });

    test('discarding clears the data and continues as the new account', () async {
      final sync = await session();
      await signInAs('user-2', 'two@example.com');
      await sync.init();
      await sync.discardPendingChanges();

      expect(sync.conflict, isNull);
      expect(await ProductDao().getById('product-1'), isNull);
      expect(await queueEmpty(), isTrue);
      expect(await storedOwner(), 'user-2');
      expect(connects, 2);
    });

    test('going back signs the new account out and keeps the changes', () async {
      final sync = await session();
      await signInAs('user-2', 'two@example.com');
      await sync.init();
      await sync.leaveForPreviousAccount();
      await sync.idle;

      expect(sync.conflict, isNull);
      expect(server.client.auth.currentSession, isNull);
      expect(await queueEmpty(), isFalse);

      // The previous account signs in again and uploads them.
      await signInAs(owner, 'one@example.com');
      await sync.init();
      expect(sync.conflict, isNull);
      await upload();
      expect(server.to('rpc/create_shop'), hasLength(1));
    });
  });
}
