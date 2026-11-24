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

  /// The shop to work in: the first shop [userId] is a member of, by when
  /// they joined. Without a [userId] (app without a backend), the first local
  /// profile. While no membership has synced yet, the local shops count only
  /// if [userId] owns the data on this device (see LocalOwner): that covers a
  /// shop created offline whose membership the server has not sent back yet,
  /// and never returns another account's shop.
  /// Null when there is no profile: onboarding is needed.
  Future<BusinessProfile?> getActiveProfile({String? userId}) async {
    final database = await db;
    if (userId == null) {
      final list = await query(orderBy: 'created_at, id', limit: 1);
      return list.isEmpty ? null : list.first;
    }
    final member = await database.getOptional(
        'SELECT p.* FROM business_profile p '
        'JOIN shop_member m ON m.profile_id = p.id '
        'WHERE m.user_id = ? ORDER BY m.created_at, p.id LIMIT 1',
        [userId]);
    if (member != null) return fromMap(member);
    final owned = await database.getOptional(
        'SELECT p.* FROM business_profile p '
        'WHERE EXISTS (SELECT 1 FROM local_owner o WHERE o.user_id = ?) '
        'ORDER BY p.created_at, p.id LIMIT 1',
        [userId]);
    return owned == null ? null : fromMap(owned);
  }

  /// The role of [userId] in the shop [profileId], or null if the membership
  /// has not synced to this device (a shop created here and not yet uploaded).
  Future<String?> getMemberRole(String profileId, String userId) async {
    final row = await (await db).getOptional(
        'SELECT role FROM shop_member WHERE profile_id = ? AND user_id = ?',
        [profileId, userId]);
    return row?['role'] as String?;
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
