import '../db/base_dao.dart';
import '../models/expense.dart';

class ExpenseDao extends BaseDao<Expense> {
  @override
  String get tableName => 'expense';

  @override
  Map<String, dynamic> toMap(Expense item) => item.toMap();

  @override
  Expense fromMap(Map<String, dynamic> map) => Expense.fromMap(map);

  @override
  void validate(Expense item) {
    check(item.amountMinor >= 0, 'Amount cannot be negative');
  }
}
