import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/db_time.dart';
import '../db/image_queue.dart';

/// Supabase Storage bucket of the product images (see
/// supabase/migrations/20261124000000_product_images.sql).
const productImageBucket = 'product-images';

/// Where the files of product images live, on the device and on the server.
///
/// `product.image_path` holds the object path `<profile_id>/<product_id>/<uuid>.jpg`.
/// Every image gets a new path, so a replaced image never serves a stale copy
/// from a cache, and the first path segment is the shop, which the storage
/// access rules check.
///
/// PowerSync syncs rows, not files, so this class moves the files:
///
/// - [save] writes a picked image to the device, which shows it at once, even
///   offline. ProductDao queues its upload in the same transaction as the
///   product row (`image_queue`).
/// - [uploadPending] and [deletePending] drain that queue. SupabaseConnector
///   calls them from `uploadData` after the rows (so a new shop exists
///   before its files), and again on a timer while a file is left. Another
///   device can see a path before its file exists; [resolve] returns null and
///   the placeholder shows until the file arrives. A Storage problem never
///   blocks the rows.
/// - [resolve] gives a file for display: the local copy, or else a download on
///   demand (kept as the local copy), or null when it cannot be had.
class ProductImageStore {
  /// [client] is null when no backend is configured: images then stay on the
  /// device. [directory] is DatabaseHelper.productImageDir.
  ProductImageStore(this.client, {required this.directory, this.requestTimeout = const Duration(seconds: 15)});

  final SupabaseClient? client;

  /// Longest wait for one Storage request; a timeout counts as retryable.
  final Duration requestTimeout;
  final Future<Directory> Function() directory;

  /// A new storage path for an image of [productId].
  static String newPath(String profileId, String productId) => '$profileId/$productId/${const Uuid().v4()}.jpg';

  Future<File> _file(String path) async {
    final root = (await directory()).path;
    final file = File(p.joinAll([root, ...p.posix.split(path)]));
    // Paths arrive from the server: never let one leave the image directory.
    if (!p.isWithin(root, file.path)) throw ArgumentError.value(path, 'path', 'Not an image path');
    return file;
  }

  /// The image file of [path] if it is on the device.
  Future<File?> localFile(String path) async {
    final file = await _file(path);
    return await file.exists() ? file : null;
  }

  /// Saves the processed [jpeg] (see processProductImage) on the device and
  /// returns its new path, to store as `image_path`.
  Future<String> save(String profileId, String productId, Uint8List jpeg) async {
    final path = newPath(profileId, productId);
    final file = await _file(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(jpeg, flush: true);
    return path;
  }

  /// Removes the local copy of [path], if any.
  Future<void> deleteLocal(String path) async {
    final file = await _file(path);
    if (await file.exists()) await file.delete();
  }

  /// A file to show for [path]: the local copy, else a download from storage,
  /// which is kept for later. Null when there is no copy and none can be
  /// fetched (offline, signed out, not uploaded yet, no backend).
  Future<File?> resolve(String path) async {
    final local = await localFile(path);
    if (local != null) return local;
    final client = this.client;
    if (client == null || client.auth.currentSession == null) return null;
    try {
      final bytes = await client.storage.from(productImageBucket).download(path);
      final file = await _file(path);
      await file.parent.create(recursive: true);
      // Write beside, then rename: a half-written file is never shown.
      final temp = File('${file.path}.part');
      await temp.writeAsBytes(bytes, flush: true);
      return await temp.rename(file.path);
    } catch (e) {
      debugPrint('Product image not available ($path): $e');
      return null;
    }
  }

  /// Uploads the queued image files. A network error, a timeout or a server
  /// outage leaves the file queued and is not thrown, so Storage problems
  /// never block the sync of rows; a rejection that retrying cannot fix is
  /// recorded in `upload_error` and skipped. Returns whether a file is left to
  /// retry.
  Future<bool> uploadPending(PowerSyncDatabase db) async {
    final client = this.client;
    if (client == null) return false;
    var left = false;
    for (final row in await db.getAll("SELECT id, path FROM image_queue WHERE op = ? ORDER BY created_at", [imageUpload])) {
      final id = row['id'] as String;
      final path = row['path'] as String;
      final file = await localFile(path);
      if (file == null) {
        // Removed or replaced since it was queued: nothing to upload.
        await _dequeue(db, id);
        continue;
      }
      try {
        await client.storage
            .from(productImageBucket)
            .uploadBinary(
              path,
              await file.readAsBytes(),
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
            )
            .timeout(requestTimeout);
      } on StorageException catch (e) {
        // 409: already there, from an upload whose queue row was not removed.
        if (e.statusCode != '409') {
          if (!isPermanentStorageError(e)) {
            debugPrint('Product image upload postponed ($path): ${e.statusCode} ${e.message}');
            left = true;
            continue;
          }
          await _recordFailure(db, imageUpload, path, e);
        }
      } catch (e) {
        debugPrint('Product image upload postponed ($path): $e');
        left = true;
        continue;
      }
      await _dequeue(db, id);
    }
    return left;
  }

  /// Removes the queued image files, from the server and from this device. A
  /// failed removal stays queued, as in [uploadPending], which also describes
  /// the result.
  Future<bool> deletePending(PowerSyncDatabase db) async {
    var left = false;
    for (final row in await db.getAll("SELECT id, path FROM image_queue WHERE op = ? ORDER BY created_at", [imageDelete])) {
      final path = row['path'] as String;
      try {
        await deleteLocal(path);
      } catch (e) {
        debugPrint('Product image file not removed ($path): $e');
      }
      final client = this.client;
      if (client != null) {
        try {
          // Removing a file that is not there succeeds.
          await client.storage.from(productImageBucket).remove([path]).timeout(requestTimeout);
        } on StorageException catch (e) {
          if (!isPermanentStorageError(e)) {
            debugPrint('Product image removal postponed ($path): ${e.statusCode} ${e.message}');
            left = true;
            continue;
          }
          await _recordFailure(db, imageDelete, path, e);
        } catch (e) {
          debugPrint('Product image removal postponed ($path): $e');
          left = true;
          continue;
        }
      }
      await _dequeue(db, row['id'] as String);
    }
    return left;
  }

  Future<void> _dequeue(PowerSyncDatabase db, String id) => db.execute('DELETE FROM image_queue WHERE id = ?', [id]);

  Future<void> _recordFailure(PowerSyncDatabase db, String op, String path, StorageException e) async {
    debugPrint('Image $op rejected, skipped: $path: ${e.statusCode} ${e.message}');
    await db.execute(
      'INSERT INTO upload_error (id, table_name, op, row_id, data, code, message, created_at) '
      'VALUES (uuid(), ?, ?, ?, NULL, ?, ?, ?)',
      ['storage.$productImageBucket', op, path, e.statusCode, e.message, toDbTime(DateTime.now())],
    );
  }

  /// Whether Storage rejected a request for good: 400 and 404 (bad request,
  /// missing bucket), 413 (too large), 415 (not a JPEG) or a 403 that names
  /// row-level security (not a member of the shop). Everything else is retried:
  /// a 5xx, 401, 408, 429, and a 403 that is really an expired or invalid token
  /// (Storage answers those with status 403 and a JWT message).
  static bool isPermanentStorageError(StorageException e) {
    final status = int.tryParse(e.statusCode ?? '');
    if (status == 400 || status == 404 || status == 413 || status == 415) return true;
    return status == 403 && e.message.toLowerCase().contains('row-level security');
  }
}
