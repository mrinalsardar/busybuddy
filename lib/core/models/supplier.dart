import 'package:equatable/equatable.dart';
import '../db/db_time.dart';

class Supplier extends Equatable {
  final String id;
  final String profileId;
  final String name;
  final String? contact;
  final String? email;
  final DateTime? createdAt;

  const Supplier({required this.id, required this.profileId, required this.name,
    this.contact, this.email, this.createdAt});

  Map<String, dynamic> toMap() => {
    'id': id, 'profile_id': profileId, 'name': name, 'contact': contact,
    'email': email, 'created_at': toDbTime(createdAt ?? DateTime.now()),
  };

  factory Supplier.fromMap(Map<String, dynamic> map) => Supplier(
    id: map['id'] as String, profileId: map['profile_id'] as String,
    name: map['name'] as String, contact: map['contact'] as String?,
    email: map['email'] as String?,
    createdAt: fromDbTime(map['created_at']),
  );

  @override
  List<Object?> get props => [id, profileId, name, contact, email];
}
