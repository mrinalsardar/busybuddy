import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

class BackupLog extends Equatable {
  final String id;
  final DateTime lastBackupAt;
  final String? driveFileId;
  final String status;
  final String? googleAccountId;
  final DateTime? createdAt;

  const BackupLog({required this.id, required this.lastBackupAt, this.driveFileId,
    this.status = 'pending', this.googleAccountId, this.createdAt});

  Map<String, dynamic> toMap() => {
    'id': id, 'last_backup_at': toDbTime(lastBackupAt),
    'drive_file_id': driveFileId, 'status': status,
    'google_account_id': googleAccountId,
    'created_at': toDbTime(createdAt ?? DateTime.now()),
  };

  factory BackupLog.fromMap(Map<String, dynamic> map) => BackupLog(
    id: map['id'] as String,
    lastBackupAt: fromDbTime(map['last_backup_at'])!,
    driveFileId: map['drive_file_id'] as String?,
    status: map['status'] as String? ?? 'pending',
    googleAccountId: map['google_account_id'] as String?,
    createdAt: fromDbTime(map['created_at']),
  );

  @override
  List<Object?> get props => [id, lastBackupAt, status];
}
