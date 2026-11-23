import '../db/base_dao.dart';
import '../models/business_profile.dart';

class BusinessProfileDao extends BaseDao<BusinessProfile> {
  @override
  String get tableName => 'business_profile';

  @override
  Map<String, dynamic> toMap(BusinessProfile item) => item.toMap();

  @override
  BusinessProfile fromMap(Map<String, dynamic> map) => BusinessProfile.fromMap(map);

  @override
  void validate(BusinessProfile item) {
    check(item.currencyDecimals >= 0 && item.currencyDecimals <= 3, 'Currency decimals must be 0 to 3');
  }

  /// A shop cannot be deleted: the server has no delete path for it, and
  /// deleting its rows here would upload deletes of the shop's shared data.
  /// Use DatabaseHelper.deleteDb to clear this device instead.
  @override
  Future<int> delete(String id) =>
      throw UnsupportedError('A shop cannot be deleted; clear local data instead');

  /// Returns the first (and typically only) profile, or null on fresh install.
  Future<BusinessProfile?> getActiveProfile() async {
    final list = await query(limit: 1);
    return list.isEmpty ? null : list.first;
  }

  /// True once the profile has any product (archived included) or sale.
  /// From then on its currency and decimals are locked.
  Future<bool> hasProductsOrSales(String profileId) async {
    final row = await (await db).get(
        'SELECT EXISTS(SELECT 1 FROM product WHERE profile_id = ?) '
        'OR EXISTS(SELECT 1 FROM sale WHERE profile_id = ?) AS used',
        [profileId, profileId]);
    return row['used'] == 1;
  }

  /// Check if a profile already exists (i.e. not a first-launch).
  Future<bool> hasProfile() async {
    return (await count()) > 0;
  }
}
