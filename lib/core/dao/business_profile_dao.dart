import 'package:sqflite/sqflite.dart';
import '../db/base_dao.dart';
import '../db/database_helper.dart';
import '../models/business_profile.dart';

class BusinessProfileDao extends BaseDao<BusinessProfile> {
  @override
  String get tableName => 'business_profile';

  @override
  Map<String, dynamic> toMap(BusinessProfile item) => item.toMap();

  @override
  BusinessProfile fromMap(Map<String, dynamic> map) => BusinessProfile.fromMap(map);

  /// Returns the first (and typically only) profile, or null on fresh install.
  Future<BusinessProfile?> getActiveProfile() async {
    final list = await query(limit: 1);
    return list.isEmpty ? null : list.first;
  }

  /// True once the profile has any product (archived included) or sale.
  /// From then on its currency and decimals are locked.
  Future<bool> hasProductsOrSales(String profileId) async {
    final db = await DatabaseHelper().database;
    return Sqflite.firstIntValue(await db.rawQuery(
            'SELECT EXISTS(SELECT 1 FROM product WHERE profile_id = ?) '
            'OR EXISTS(SELECT 1 FROM sale WHERE profile_id = ?)',
            [profileId, profileId])) ==
        1;
  }

  /// Check if a profile already exists (i.e. not a first-launch).
  Future<bool> hasProfile() async {
    return (await count()) > 0;
  }
}
