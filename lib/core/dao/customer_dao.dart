import '../db/base_dao.dart';
import '../models/customer.dart';

class CustomerDao extends BaseDao<Customer> {
  @override
  String get tableName => 'customer';

  @override
  Map<String, dynamic> toMap(Customer item) => item.toMap();

  @override
  Customer fromMap(Map<String, dynamic> map) => Customer.fromMap(map);

  /// Deletes a customer; their sales stay, with no customer.
  @override
  Future<int> delete(String id) async {
    return (await db).writeTransaction((tx) async {
      await tx.execute('UPDATE sale SET customer_id = NULL WHERE customer_id = ?', [id]);
      return deleteRow(tx, tableName, id);
    });
  }

  /// Lifetime spend in minor units, calculated from the customer's sales
  /// rather than stored, so it can't drift from them.
  Future<int> getTotalSpentMinor(String customerId) async {
    final row = await (await db).get(
        'SELECT COALESCE(SUM(total_minor), 0) AS total FROM sale WHERE customer_id = ?', [customerId]);
    return row['total'] as int;
  }
}
