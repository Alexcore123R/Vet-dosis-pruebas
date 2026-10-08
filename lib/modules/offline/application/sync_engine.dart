import '../../auth/domain/clinic_membership.dart';
import 'dart:convert';
import '../domain/offline_models.dart';

abstract interface class SyncAuthority {
  String? get userId;
  Future<ClinicRole?> cachedRole(SyncScope scope);
  Future<ClinicRole?> onlineRole(SyncScope scope);
}

class PushResult {
  const PushResult.applied() : conflict = false;
  const PushResult.conflict() : conflict = true;
  final bool conflict;
}

abstract interface class SyncAdapter {
  String get kind;
  bool get permitsOfflineQueue;
  bool canWrite(ClinicRole role);
  bool accepts(Mutation mutation);
  // Backend MUST atomically check expectedVersion and persist the idempotency receipt.
  // Authorization MUST also be enforced server-side; client checks are supplemental.
  Future<PushResult> push(Mutation mutation);
}

class SyncEngine {
  SyncEngine(
    this.store,
    this.authority,
    Iterable<SyncAdapter> adapters, {
    DateTime Function()? now,
  }) : adapters = {for (final a in adapters) a.kind: a},
       now = now ?? DateTime.now;
  final SyncStore store;
  final SyncAuthority authority;
  final Map<String, SyncAdapter> adapters;
  final DateTime Function() now;
  bool _running = false;
  Future<void> enqueue(Mutation mutation) async {
    final adapter = adapters[mutation.kind];
    if (mutation.scope.userId != authority.userId ||
        adapter == null ||
        !adapter.accepts(mutation)) {
      throw StateError('Unsupported mutation or scope');
    }
    final role = adapter.permitsOfflineQueue
        ? await authority.cachedRole(mutation.scope)
        : await authority.onlineRole(mutation.scope);
    if (mutation.scope.userId != authority.userId ||
        role == null ||
        !adapter.canWrite(role)) {
      throw StateError('Permission required');
    }
    await store.enqueue(mutation);
  }

  Future<void> synchronize(SyncScope scope) async {
    if (_running || scope.userId != authority.userId) return;
    _running = true;
    try {
      final blockedRecords = <String>{};
      for (final item in await store.queue(scope)) {
        final recordKey = jsonEncode([
          item.mutation.kind,
          item.mutation.recordId,
        ]);
        if (blockedRecords.contains(recordKey)) continue;
        if (scope.userId != authority.userId) break;
        if (item.state == QueueState.conflict ||
            item.state == QueueState.blocked) {
          blockedRecords.add(recordKey);
          continue;
        }
        if (item.nextAttemptAt?.isAfter(now()) ?? false) break;
        final adapter = adapters[item.mutation.kind];
        try {
          final role = await authority.onlineRole(scope);
          if (scope.userId != authority.userId) break;
          if (role == null ||
              adapter == null ||
              !adapter.canWrite(role) ||
              !adapter.accepts(item.mutation)) {
            blockedRecords.add(recordKey);
            await store.update(
              QueueItem(
                item.mutation,
                state: QueueState.blocked,
                attempts: item.attempts,
                reason: 'permission_or_adapter_changed',
              ),
            );
            continue;
          }
          final result = await adapter.push(item.mutation);
          if (result.conflict) {
            blockedRecords.add(recordKey);
            await store.update(
              QueueItem(
                item.mutation,
                state: QueueState.conflict,
                attempts: item.attempts + 1,
                reason: 'version_conflict',
              ),
            );
          } else {
            await store.remove(item.mutation);
          }
        } on NetworkUnavailable {
          final attempts = item.attempts + 1;
          final seconds = 5 * (1 << (attempts > 7 ? 7 : attempts - 1));
          await store.update(
            QueueItem(
              item.mutation,
              state: QueueState.retry,
              attempts: attempts,
              nextAttemptAt: now().toUtc().add(Duration(seconds: seconds)),
              reason: 'network_unavailable',
            ),
          );
          break;
        } catch (_) {
          blockedRecords.add(recordKey);
          await store.update(
            QueueItem(
              item.mutation,
              state: QueueState.blocked,
              attempts: item.attempts + 1,
              reason: 'requires_review',
            ),
          );
        }
      }
    } finally {
      _running = false;
    }
  }
}
