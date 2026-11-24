import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:busybuddy/core/dao/daos.dart';
import 'package:busybuddy/core/db/database_helper.dart';
import 'package:busybuddy/core/db/supabase_connector.dart';
import 'package:busybuddy/core/images/product_image_store.dart';
import 'package:busybuddy/core/models/models.dart';

import 'supabase_connector_test.dart' show sell, signIn;
import 'test_db.dart';

const profile = BusinessProfile(id: 'profile-1', name: 'Shop', type: BusinessType.general);
const product = Product(id: 'product-1', profileId: 'profile-1', name: 'Laces', priceMinor: 9999, stockQty: 10);

/// One request the app sent to the fake Supabase.
class Req {
  final String method;
  final String path;
  final Uint8List body;
  Req(http.Request r)
      : method = r.method,
        path = r.url.path,
        body = r.bodyBytes;

  /// The storage object path of an object request.
  String get object => path.replaceFirst('/storage/v1/object/$productImageBucket/', '');
  bool get isStorage => path.startsWith('/storage/v1/');

  @override
  String toString() => '$method $path';
}

/// A Supabase with Storage that records requests and answers from [reply]
/// (a status for a failure, null for success).
class Backend {
  final requests = <Req>[];
  int? Function(Req request) reply = (_) => null;
  bool offline = false;
  final files = <String, Uint8List>{};

  late final client = SupabaseClient(
    'http://supabase.test',
    'anon-key',
    httpClient: MockClient((request) async {
      final r = Req(request);
      requests.add(r);
      if (offline) throw const SocketException('offline');
      final status = reply(r);
      if (status != null) {
        return http.Response(jsonEncode({'message': 'rejected $status', 'error': 'x'}), status,
            request: request, headers: {'content-type': 'application/json'});
      }
      final json = {'content-type': 'application/json'};
      if (r.isStorage) {
        if (r.method == 'GET') return http.Response.bytes(files[r.object] ?? Uint8List(0), 200, request: request);
        if (r.method == 'POST') {
          return http.Response(jsonEncode({'Key': '$productImageBucket/${r.object}', 'Id': '1'}), 200,
              request: request, headers: json);
        }
        return http.Response('[]', 200, request: request, headers: json);
      }
      return http.Response('', 200, request: request);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  Iterable<Req> get storage => requests.where((r) => r.isStorage);
}

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  useTestDatabase();

  late Backend backend;
  late ProductImageStore store;

  Future<List<Map<String, Object?>>> queue() async => [
        for (final r in await (await DatabaseHelper().database).getAll('SELECT op, path FROM image_queue ORDER BY op, path'))
          {...r}
      ];

  setUp(() async {
    backend = Backend();
    store = ProductImageStore(backend.client, directory: DatabaseHelper().productImageDir);
    await signIn(backend.client);
    await BusinessProfileDao().insert(profile);
  });

  group('product dao', () {
    Future<String> addImage({Product p = product}) async {
      final path = await store.save(profile.id, p.id, bytes('jpeg'));
      await ProductDao().saveWithVariants(p.copyWith(imagePath: path), isNew: true);
      return path;
    }

    test('a new product with a picture stores its path and queues the upload', () async {
      final path = await addImage();

      expect((await ProductDao().getById(product.id))!.imagePath, path);
      expect(await queue(), [
        {'op': 'upload', 'path': path}
      ]);
    });

    test('a product without a picture queues nothing', () async {
      await ProductDao().insert(product);
      await ProductDao().update(product.copyWith(name: 'Laces 2'), product.id);

      expect(await queue(), isEmpty);
    });

    test('an edit that keeps the picture queues nothing more', () async {
      final path = await addImage();
      await (await DatabaseHelper().database).execute('DELETE FROM image_queue');

      await ProductDao().update(product.copyWith(name: 'Laces 2', imagePath: path), product.id);

      expect(await queue(), isEmpty);
    });

    test('replacing the picture queues the new upload and the old deletion', () async {
      final old = await addImage();
      await (await DatabaseHelper().database).execute('DELETE FROM image_queue');
      final replacement = await store.save(profile.id, product.id, bytes('jpeg 2'));

      await ProductDao().update(product.copyWith(imagePath: replacement), product.id);

      expect((await ProductDao().getById(product.id))!.imagePath, replacement);
      expect(await queue(), [
        {'op': 'delete', 'path': old},
        {'op': 'upload', 'path': replacement},
      ]);
    });

    test('a picture replaced before it uploaded is not uploaded', () async {
      final first = await addImage();
      final second = await store.save(profile.id, product.id, bytes('jpeg 2'));

      await ProductDao().update(product.copyWith(imagePath: second), product.id);

      expect(await queue(), [
        {'op': 'delete', 'path': first},
        {'op': 'upload', 'path': second},
      ]);
    });

    test('removing the picture clears the path and queues the deletion', () async {
      final path = await addImage();
      await ProductDao().update(const Product(id: 'product-1', profileId: 'profile-1', name: 'Laces'), product.id);

      expect((await ProductDao().getById(product.id))!.imagePath, isNull);
      expect(await queue(), [
        {'op': 'delete', 'path': path}
      ]);
    });

    test('archiving a product removes its picture', () async {
      final path = await addImage();

      await ProductDao().archive(product.id);

      final archived = (await ProductDao().getById(product.id))!;
      expect(archived.archived, isTrue);
      expect(archived.imagePath, isNull);
      expect(await queue(), [
        {'op': 'delete', 'path': path}
      ]);
    });

    test('deleting a product queues the deletion of its picture', () async {
      final path = await addImage();

      await ProductDao().delete(product.id);

      expect(await ProductDao().getById(product.id), isNull);
      expect(await queue(), [
        {'op': 'delete', 'path': path}
      ]);
    });
  });

  group('store', () {
    test('a saved picture is on the device under the shop and product', () async {
      final path = await store.save('shop', 'prod', bytes('jpeg'));

      expect(path, matches(RegExp(r'^shop/prod/[0-9a-f-]{36}\.jpg$')));
      expect(await (await store.localFile(path))!.readAsBytes(), bytes('jpeg'));
      // Shown without any network or session.
      backend.offline = true;
      expect(await store.resolve(path), isNotNull);
      expect(backend.requests, isEmpty);

      await store.deleteLocal(path);
      expect(await store.localFile(path), isNull);
    });

    test('a path leaving the image directory is refused', () async {
      await expectLater(store.localFile('../busybuddy.db'), throwsArgumentError);
      await expectLater(store.resolve('shop/../../x.jpg'), throwsArgumentError);
    });

    test('a missing picture is downloaded on demand and kept', () async {
      backend.files['shop/prod/a.jpg'] = bytes('remote');

      final file = (await store.resolve('shop/prod/a.jpg'))!;
      expect(await file.readAsBytes(), bytes('remote'));
      expect(backend.storage.map((r) => r.method), ['GET']);

      backend.offline = true;
      expect(await store.resolve('shop/prod/a.jpg'), isNotNull);
      expect(backend.storage, hasLength(1));
    });

    test('a picture that cannot be fetched gives null', () async {
      backend.offline = true;
      expect(await store.resolve('shop/prod/a.jpg'), isNull);

      backend.offline = false;
      backend.reply = (_) => 404;
      expect(await store.resolve('shop/prod/a.jpg'), isNull);
      expect(await store.localFile('shop/prod/a.jpg'), isNull);

      final noBackend = ProductImageStore(null, directory: DatabaseHelper().productImageDir);
      expect(await noBackend.resolve('shop/prod/a.jpg'), isNull);
    });

    group('uploading', () {
      late String path;
      late Future<void> Function() upload;

      setUp(() async {
        path = await store.save(profile.id, product.id, bytes('jpeg'));
        await ProductDao().saveWithVariants(product.copyWith(imagePath: path), isNew: true);
        upload = () async => store.uploadPending(await DatabaseHelper().database);
      });

      test('sends the file to the shop folder and leaves the queue', () async {
        await upload();

        final put = backend.storage.single;
        expect(put.method, 'POST');
        expect(put.object, path);
        expect(utf8.decode(put.body, allowMalformed: true), contains('jpeg'));
        expect(await queue(), isEmpty);
        // The device keeps showing its own copy.
        expect(await store.localFile(path), isNotNull);
      });

      test('an object that already exists counts as uploaded', () async {
        backend.reply = (_) => 409;
        await upload();
        expect(await queue(), isEmpty);
      });

      test('a rejection that retrying cannot fix is recorded and skipped', () async {
        backend.reply = (_) => 403;
        await upload();

        expect(await queue(), isEmpty);
        final errors = await (await DatabaseHelper().database).getAll('SELECT * FROM upload_error');
        expect(errors.single['table_name'], 'storage.$productImageBucket');
        expect(errors.single['row_id'], path);
        expect(errors.single['code'], '403');
      });

      test('a server error or no network keeps it queued for a retry', () async {
        backend.reply = (_) => 503;
        await upload();
        backend.reply = (_) => null;
        backend.offline = true;
        await upload();

        expect(await queue(), [
          {'op': 'upload', 'path': path}
        ]);

        backend.offline = false;
        await upload();
        expect(await queue(), isEmpty);
      });

      test('a file that is gone locally is dropped from the queue', () async {
        await store.deleteLocal(path);
        await upload();

        expect(backend.requests, isEmpty);
        expect(await queue(), isEmpty);
      });
    });

    test('queued deletions remove the file from the server and the device', () async {
      final path = await store.save(profile.id, product.id, bytes('jpeg'));
      await ProductDao().saveWithVariants(product.copyWith(imagePath: path), isNew: true);
      await ProductDao().archive(product.id);

      await store.deletePending(await DatabaseHelper().database);

      final remove = backend.storage.single;
      expect(remove.method, 'DELETE');
      expect(jsonDecode(utf8.decode(remove.body)), {'prefixes': [path]});
      expect(await store.localFile(path), isNull);
      expect(await queue(), isEmpty);
    });

    test('a deletion without network stays queued', () async {
      final path = await store.save(profile.id, product.id, bytes('jpeg'));
      await ProductDao().saveWithVariants(product.copyWith(imagePath: path), isNew: true);
      await ProductDao().archive(product.id);
      backend.offline = true;

      await store.deletePending(await DatabaseHelper().database);

      expect(await queue(), [
        {'op': 'delete', 'path': path}
      ]);
    });
  });

  test('the connector uploads a picture before its product row, and deletes the old one after', () async {
    final connector = SupabaseConnector(backend.client, powerSyncUrl: 'http://powersync.test', images: store);
    final db = await DatabaseHelper().database;
    final first = await store.save(profile.id, product.id, bytes('jpeg'));
    await ProductDao().saveWithVariants(product.copyWith(imagePath: first), isNew: true);
    await connector.uploadData(db);
    backend.requests.clear();

    final second = await store.save(profile.id, product.id, bytes('jpeg 2'));
    await ProductDao().update(product.copyWith(imagePath: second), product.id);
    await connector.uploadData(db);

    expect(backend.requests.map((r) => r.method == 'POST' && r.isStorage ? 'POST ${r.object}' : '${r.method} ${r.path}'), [
      'POST $second',
      'PATCH /rest/v1/product',
      'DELETE /storage/v1/object/product-images',
    ]);
    expect(await db.getNextCrudTransaction(), isNull);
    expect(await queue(), isEmpty);
  });

  test('the connector keeps product changes waiting while the network is down', () async {
    final connector = SupabaseConnector(backend.client, powerSyncUrl: 'http://powersync.test', images: store);
    final db = await DatabaseHelper().database;
    final path = await store.save(profile.id, product.id, bytes('jpeg'));
    await ProductDao().saveWithVariants(product.copyWith(imagePath: path), isNew: true);
    backend.offline = true;

    await expectLater(connector.uploadData(db), throwsA(anything));

    expect(await db.getNextCrudTransaction(), isNotNull);
    expect(await queue(), [
      {'op': 'upload', 'path': path}
    ]);
  });

  test('a Storage outage does not hold back the product row or a sale', () async {
    final connector = SupabaseConnector(backend.client, powerSyncUrl: 'http://powersync.test', images: store);
    final db = await DatabaseHelper().database;
    final path = await store.save(profile.id, product.id, bytes('jpeg'));
    await ProductDao().saveWithVariants(product.copyWith(imagePath: path), isNew: true);
    await sell(product);
    backend.reply = (r) => r.isStorage ? 503 : null;

    await connector.uploadData(db);

    expect(backend.requests.where((r) => !r.isStorage).map((r) => r.path), containsAll(['/rest/v1/product', '/rest/v1/rpc/record_sale']));
    expect(await db.getNextCrudTransaction(), isNull);
    expect(await queue(), [
      {'op': 'upload', 'path': path}
    ]);
  });
}
