import 'package:sembast/sembast.dart';
import 'dart:convert';
import '../../auth/domain/clinic_membership.dart';
import '../domain/offline_models.dart';

class LocalStore implements AccessCache, SyncStore {
  LocalStore(this.database);
  final Database database;
  final _access = stringMapStoreFactory.store('access-v1');
  final _sequence = StoreRef<String, int>('sequence-v1');
  final _outbox = stringMapStoreFactory.store('outbox-v1');
  String _key(Mutation mutation) =>
      jsonEncode([mutation.scope.userId, mutation.scope.clinicId, mutation.id]);
  @override
  Future<MembershipSnapshot?> readAccess(String userId) async {
    final row = await _access.record(userId).get(database);
    if (row == null) return null;
    if (row['userId'] != userId) {
      throw const FormatException('Invalid access scope');
    }
    return MembershipSnapshot(
      userId,
      (row['members'] as List).map((value) {
        final m = value as Map;
        return ClinicMembership(
          clinicId: m['clinicId'] as String,
          clinicName: m['clinicName'] as String,
          userId: m['userId'] as String,
          role: ClinicRole.parse(m['role'] as String),
          workspaceKind: m['workspaceKind'] as String? ?? 'clinic',
        );
      }).toList(),
      DateTime.fromMillisecondsSinceEpoch(
        row['verifiedAt'] as int,
        isUtc: true,
      ),
    );
  }

  @override
  Future<void> writeAccess(MembershipSnapshot snapshot) async {
    await _access.record(snapshot.userId).put(database, {
      'userId': snapshot.userId,
      'verifiedAt': snapshot.verifiedAt.toUtc().millisecondsSinceEpoch,
      'members': snapshot.members
          .map(
            (m) => {
              'clinicId': m.clinicId,
              'clinicName': m.clinicName,
              'userId': m.userId,
              'role': m.role.name,
              'workspaceKind': m.workspaceKind,
            },
          )
          .toList(),
    });
  }

  @override
  Future<void> clearAccess(String userId) =>
      _access.record(userId).delete(database).then((_) {});
  Map<String, Object?> _row(QueueItem item) => {
    'userId': item.mutation.scope.userId,
    'clinicId': item.mutation.scope.clinicId,
    'id': item.mutation.id,
    'kind': item.mutation.kind,
    'recordId': item.mutation.recordId,
    'expectedVersion': item.mutation.expectedVersion,
    'action': item.mutation.action.name,
    'payloadJson': item.mutation.payloadJson,
    'state': item.state.name,
    'attempts': item.attempts,
    'nextAttemptAt': item.nextAttemptAt?.toUtc().millisecondsSinceEpoch,
    'reason': item.reason,
  };
  QueueItem _item(Map<String, Object?> row) => QueueItem(
    Mutation(
      id: row['id'] as String,
      scope: SyncScope(row['userId'] as String, row['clinicId'] as String),
      kind: row['kind'] as String,
      recordId: row['recordId'] as String,
      expectedVersion: row['expectedVersion'] as int,
      action: MutationAction.values.byName(row['action'] as String),
      payload: Map<String, Object?>.from(
        jsonDecode(row['payloadJson'] as String) as Map,
      ),
    ),
    state: QueueState.values.byName(row['state'] as String),
    attempts: row['attempts'] as int,
    nextAttemptAt: row['nextAttemptAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row['nextAttemptAt'] as int,
            isUtc: true,
          ),
    reason: row['reason'] as String?,
  );
  @override
  Future<void> enqueue(Mutation mutation) => database.transaction((txn) async {
    final record = _outbox.record(_key(mutation));
    final old = await record.get(txn);
    final next = _row(QueueItem(mutation));
    if (old != null) {
      final previous = _item(old).mutation;
      if (previous.payloadJson != mutation.payloadJson ||
          previous.kind != mutation.kind ||
          previous.recordId != mutation.recordId ||
          previous.expectedVersion != mutation.expectedVersion ||
          previous.action != mutation.action) {
        throw StateError('Idempotency key reused');
      }
      return;
    }
    final sequence = (await _sequence.record('next').get(txn) ?? 0) + 1;
    await _sequence.record('next').put(txn, sequence);
    await record.put(txn, {...next, 'sequence': sequence});
  });
  @override
  Future<List<QueueItem>> queue(SyncScope scope) async {
    final rows = await _outbox.find(
      database,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('userId', scope.userId),
          Filter.equals('clinicId', scope.clinicId),
        ]),
        sortOrders: [SortOrder('sequence')],
      ),
    );
    return rows.map((row) => _item(row.value)).toList();
  }

  @override
  Future<void> update(QueueItem item) => database.transaction((txn) async {
    final record = _outbox.record(_key(item.mutation));
    final old = await record.get(txn);
    if (old != null) {
      await record.put(txn, {..._row(item), 'sequence': old['sequence']});
    }
  });
  @override
  Future<void> remove(Mutation mutation) =>
      _outbox.record(_key(mutation)).delete(database).then((_) {});
  @override
  Future<int> pendingForUser(String userId) =>
      _outbox.count(database, filter: Filter.equals('userId', userId));
  @override
  Future<void> purgeUser(String userId) => database.transaction((txn) async {
    await _access.record(userId).delete(txn);
    await _outbox.delete(
      txn,
      finder: Finder(filter: Filter.equals('userId', userId)),
    );
  });
}
