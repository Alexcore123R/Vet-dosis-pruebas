import 'dart:convert';
import '../../auth/domain/clinic_membership.dart';

class NetworkUnavailable implements Exception {
  const NetworkUnavailable();
}

class PendingChanges implements Exception {
  const PendingChanges();
}

class MembershipSnapshot {
  MembershipSnapshot(
    this.userId,
    List<ClinicMembership> members,
    this.verifiedAt,
  ) : members = List.unmodifiable(members) {
    if (members.any((member) => member.userId != userId)) {
      throw const FormatException('Snapshot belongs to another user');
    }
  }
  final String userId;
  final List<ClinicMembership> members;
  final DateTime verifiedAt;
  bool validAt(DateTime now, Duration maxAge) {
    final age = now.toUtc().difference(verifiedAt.toUtc());
    return !age.isNegative && age < maxAge;
  }
}

abstract interface class AccessCache {
  Future<MembershipSnapshot?> readAccess(String userId);
  Future<void> writeAccess(MembershipSnapshot snapshot);
  Future<void> clearAccess(String userId);
}

class SyncScope {
  const SyncScope(this.userId, this.clinicId);
  final String userId;
  final String clinicId;
}

enum MutationAction { upsert, delete }

enum QueueState { pending, retry, conflict, blocked }

class Mutation {
  Mutation({
    required this.id,
    required this.scope,
    required this.kind,
    required this.recordId,
    required this.expectedVersion,
    required Map<String, Object?> payload,
    this.action = MutationAction.upsert,
  }) : payloadJson = jsonEncode(payload) {
    if ([
          id,
          scope.userId,
          scope.clinicId,
          kind,
          recordId,
        ].any((s) => s.isEmpty) ||
        expectedVersion < 0) {
      throw const FormatException('Invalid mutation');
    }
  }
  final String
  id; // Globally unique operation/idempotency key supplied by domain adapter.
  final SyncScope scope;
  final String kind;
  final String recordId;
  final int expectedVersion;
  final MutationAction action;
  final String payloadJson;
  Map<String, Object?> get payload =>
      Map<String, Object?>.from(jsonDecode(payloadJson) as Map);
}

class QueueItem {
  const QueueItem(
    this.mutation, {
    this.state = QueueState.pending,
    this.attempts = 0,
    this.nextAttemptAt,
    this.reason,
  });
  final Mutation mutation;
  final QueueState state;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? reason;
}

abstract interface class SyncStore {
  Future<void> enqueue(Mutation mutation);
  Future<List<QueueItem>> queue(SyncScope scope);
  Future<void> update(QueueItem item);
  Future<void> remove(Mutation mutation);
  Future<int> pendingForUser(String userId);
  Future<void> purgeUser(String userId);
}
