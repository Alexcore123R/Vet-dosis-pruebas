import '../../auth/domain/auth_repository.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/offline_models.dart';
import 'sync_engine.dart';

class MembershipSyncAuthority implements SyncAuthority {
  MembershipSyncAuthority(
    this.repository,
    this.cache, {
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final AuthRepository repository;
  final AccessCache cache;
  final DateTime Function() now;
  @override
  String? get userId => repository.userId;
  @override
  Future<ClinicRole?> cachedRole(SyncScope scope) async {
    if (scope.userId != userId) return null;
    final snapshot = await cache.readAccess(scope.userId);
    if (snapshot == null ||
        !snapshot.validAt(now(), const Duration(hours: 24))) {
      return null;
    }
    return snapshot.members
        .where((member) => member.clinicId == scope.clinicId)
        .firstOrNull
        ?.role;
  }

  @override
  Future<ClinicRole?> onlineRole(SyncScope scope) async {
    if (scope.userId != userId) return null;
    final members = await repository.memberships();
    if (scope.userId != userId) return null;
    await cache.writeAccess(
      MembershipSnapshot(scope.userId, members, now().toUtc()),
    );
    return members
        .where((member) => member.clinicId == scope.clinicId)
        .firstOrNull
        ?.role;
  }
}
