import 'package:sqflite/sqflite.dart';
import '../db/base_dao.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';

class CustomerDao extends BaseDao<Customer> {
  @override
  String get tableName => 'customer';

  @override
  Map<String, dynamic> toMap(Customer item) => item.toMap();

  @override
  Customer fromMap(Map<String, dynamic> map) => Customer.fromMap(map);

  /// Lifetime spend in minor units, calculated from the customer's sales
  /// rather than stored, so it can't drift from them.
  Future<int> getTotalSpentMinor(String customerId) async {
    final db = await DatabaseHelper().database;
    return Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COALESCE(SUM(total_minor), 0) FROM sale WHERE customer_id = ?',
        [customerId]))!;
  }
}
