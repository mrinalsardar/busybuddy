import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;

import 'db_time.dart';

/// The local-only `image_queue` table: product image files that must still be
/// uploaded to, or removed from, Supabase Storage. Rows are added in the same
/// transaction as the product change that needs them, and drained by
/// ProductImageStore (from SupabaseConnector.uploadData).
const imageUpload = 'upload';
const imageDelete = 'delete';

/// Queues the upload of the image file at [path] (a product's `image_path`).
Future<void> queueImageUpload(SqliteWriteContext tx, String path) => _queue(tx, imageUpload, path);

/// Queues the removal of the image file at [path]. A pending upload of the same
/// file is dropped: the file is not wanted any more.
Future<void> queueImageDelete(SqliteWriteContext tx, String path) async {
  await tx.execute("DELETE FROM image_queue WHERE op = 'upload' AND path = ?", [path]);
  await _queue(tx, imageDelete, path);
}

Future<void> _queue(SqliteWriteContext tx, String op, String path) async {
  if (await tx.getOptional('SELECT 1 FROM image_queue WHERE op = ? AND path = ?', [op, path]) != null) return;
  await tx.execute(
    'INSERT INTO image_queue (id, op, path, created_at) VALUES (uuid(), ?, ?, ?)',
    [op, path, toDbTime(DateTime.now())],
  );
}
