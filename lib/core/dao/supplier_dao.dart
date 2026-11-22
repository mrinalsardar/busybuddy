import '../db/base_dao.dart';
import '../models/supplier.dart';

class SupplierDao extends BaseDao<Supplier> {
  @override
  String get tableName => 'supplier';

  @override
  Map<String, dynamic> toMap(Supplier item) => item.toMap();

  @override
  Supplier fromMap(Map<String, dynamic> map) => Supplier.fromMap(map);
}
