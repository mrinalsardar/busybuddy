import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

class Expense extends Equatable {
  final String id;
  final String profileId;
  /// Amount in minor units (see core/utils/money.dart).
  final int amountMinor;
  final String? category;
  final String? note;
  final DateTime date;
  final DateTime? createdAt;

  const Expense({required this.id, required this.profileId, required this.amountMinor,
    this.category, this.note, required this.date, this.createdAt});

  Map<String, dynamic> toMap() => {
    'id': id, 'profile_id': profileId, 'amount_minor': amountMinor, 'category': category,
    'note': note, 'date': toDbDate(date),
    'created_at': toDbTime(createdAt ?? DateTime.now()),
  };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
    id: map['id'] as String, profileId: map['profile_id'] as String,
    amountMinor: map['amount_minor'] as int? ?? 0,
    category: map['category'] as String?, note: map['note'] as String?,
    date: fromDbDate(map['date'])!,
    createdAt: fromDbTime(map['created_at']),
  );

  @override
  List<Object?> get props => [id, profileId, amountMinor, category, date];
}
