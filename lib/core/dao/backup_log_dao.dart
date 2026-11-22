import '../db/base_dao.dart';
import '../models/backup_log.dart';

class BackupLogDao extends BaseDao<BackupLog> {
  @override
  String get tableName => 'backup_log';

  @override
  Map<String, dynamic> toMap(BackupLog item) => item.toMap();

  @override
  BackupLog fromMap(Map<String, dynamic> map) => BackupLog.fromMap(map);

  Future<BackupLog?> getLatest() async {
    final list = await query(orderBy: 'last_backup_at DESC', limit: 1);
    return list.isEmpty ? null : list.first;
  }
}
