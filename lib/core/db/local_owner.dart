import 'package:powersync/powersync.dart';

/// The account that owns the data on this device.
///
/// A forced sign-out keeps local data and the upload queue, so a different
/// account can sign in on top of them. Recording the owner lets sign-in
/// notice that, instead of showing one user's shop to another or uploading
/// their queued changes under the wrong token. The row is local-only and is
/// cleared together with the data.
class LocalOwner {
  const LocalOwner({required this.userId, this.email});

  final String userId;

  /// Shown to the user so they know which account to sign back in with.
  final String? email;

  static const _rowId = 'owner';

  /// The owner, or null when no account has claimed the data yet (a fresh
  /// install, or data from before owners were recorded).
  static Future<LocalOwner?> read(PowerSyncDatabase db) async {
    final row = await db.getOptional('SELECT user_id, email FROM local_owner WHERE id = ?', [_rowId]);
    final userId = row?['user_id'] as String?;
    return userId == null ? null : LocalOwner(userId: userId, email: row?['email'] as String?);
  }

  /// Makes [userId] the owner of the data.
  static Future<void> write(PowerSyncDatabase db, String userId, String? email) =>
      db.writeTransaction((tx) async {
        await tx.execute('DELETE FROM local_owner');
        await tx.execute(
            'INSERT INTO local_owner (id, user_id, email) VALUES (?, ?, ?)', [_rowId, userId, email]);
      });

  /// True while changes made on this device wait to upload.
  static Future<bool> hasPendingUploads(PowerSyncDatabase db) async =>
      await db.getNextCrudTransaction() != null;
}
