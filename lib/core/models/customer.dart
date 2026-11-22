import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

class Customer extends Equatable {
  final String id;
  final String profileId;
  final String name;
  final String? phone;
  final String? email;
  final DateTime? createdAt;

  const Customer({
    required this.id,
    required this.profileId,
    required this.name,
    this.phone,
    this.email,
    this.createdAt,
  });

  Customer copyWith({String? id, String? profileId, String? name, String? phone, String? email, DateTime? createdAt}) {
    return Customer(id: id ?? this.id, profileId: profileId ?? this.profileId, name: name ?? this.name, phone: phone ?? this.phone,
      email: email ?? this.email, createdAt: createdAt ?? this.createdAt);
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'profile_id': profileId, 'name': name, 'phone': phone, 'email': email,
    'created_at': toDbTime(createdAt ?? DateTime.now()),
  };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
    id: map['id'] as String, profileId: map['profile_id'] as String,
    name: map['name'] as String,
    phone: map['phone'] as String?, email: map['email'] as String?,
    createdAt: fromDbTime(map['created_at']),
  );

  @override
  List<Object?> get props => [id, profileId, name, phone, email];
}
