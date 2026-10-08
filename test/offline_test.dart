import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast_io.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/offline/data/local_store.dart';
import 'package:vetdosis_pro/modules/offline/domain/offline_models.dart';
import 'package:vetdosis_pro/modules/offline/application/sync_engine.dart';
import 'support/fake_auth.dart';

class OfflineAuth extends FakeAuth {
  bool disconnected = false;
  @override
  Future<List<ClinicMembership>> memberships() {
    if (disconnected && userId != null) throw const NetworkUnavailable();
    return super.memberships();
  }
}

class FakeAuthority implements SyncAuthority {
  @override
  String? userId = 'user-a';
  ClinicRole? role = ClinicRole.mvz;
  @override
  Future<ClinicRole?> cachedRole(SyncScope scope) async => ClinicRole.mvz;
  @override
  Future<ClinicRole?> onlineRole(SyncScope scope) async => role;
}

class DemoAdapter implements SyncAdapter {
  @override
  String get kind => 'demo';
  @override
  bool get permitsOfflineQueue => true;
  @override
  bool canWrite(ClinicRole role) => role == ClinicRole.mvz;
  @override
  bool accepts(Mutation mutation) => mutation.payload['title'] is String;
  final receipts = <String, PushResult>{};
  int version = 0;
  int requests = 0;
  bool loseAcknowledgement = false;
  bool forceConflict = false;
  @override
  Future<PushResult> push(Mutation mutation) async {
    requests++;
    if (receipts.containsKey(mutation.id)) return receipts[mutation.id]!;
    if (forceConflict || mutation.expectedVersion != version) {
      return const PushResult.conflict();
    }
    version++;
    receipts[mutation.id] = const PushResult.applied();
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw const NetworkUnavailable();
    }
    return const PushResult.applied();
  }
}

Mutation mutation(
  String id, {
  String user = 'user-a',
  String clinic = 'a',
  int version = 0,
  String record = 'record',
  String kind = 'demo',
  String title = 'demo',
}) => Mutation(
  id: id,
  scope: SyncScope(user, clinic),
  kind: kind,
  recordId: record,
  expectedVersion: version,
  payload: {'title': title},
);
void main() {
  late LocalStore store;
  late DateTime now;
  late OfflineAuth repo;
  late AuthViewModel auth;
  setUp(() async {
    store = LocalStore(
      await databaseFactoryMemory.openDatabase(
        'offline-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    now = DateTime.utc(2026, 10, 6, 12);
    repo = OfflineAuth();
    auth = AuthViewModel(repo, cache: store, syncStore: store, now: () => now);
  });
  tearDown(() async {
    auth.dispose();
    await repo.controller.close();
    await store.database.close();
  });
  test(
    'Membresía verificada permite acceso offline y bloquea gestión de equipo',
    () async {
      await auth.start();
      repo.disconnected = true;
      await auth.refresh();
      expect(auth.offline, isTrue);
      expect(auth.active?.clinicId, 'a');
      await auth.invite('someone@example.test', ClinicRole.admin);
      expect(repo.inviteCalls, 0);
      expect(auth.error, contains('Conéctate'));
    },
  );
  test(
    'Caché caduca a las 24 horas y no admite reloj anterior a la verificación',
    () async {
      await auth.start();
      repo.disconnected = true;
      now = now.add(const Duration(hours: 24));
      await auth.refresh();
      expect(auth.active, isNull);
      now = now.subtract(const Duration(hours: 25));
      await auth.refresh();
      expect(auth.active, isNull);
    },
  );
  test('Un error de permisos no se convierte en acceso offline', () async {
    await auth.start();
    repo.failRead = true;
    await auth.refresh();
    expect(auth.active, isNull);
    expect(await store.readAccess('user-a'), isNull);
  });
  test('Cambiar de usuario no recupera membresías del anterior', () async {
    await auth.start();
    repo.userId = 'user-b';
    repo.disconnected = true;
    await auth.refresh();
    expect(auth.active, isNull);
    expect(await store.readAccess('user-a'), isNull);
  });
  test('Cerrar sesión sin pendientes limpia el acceso guardado', () async {
    await auth.start();
    repo.disconnected = true;
    await auth.refresh();
    await auth.signOut();
    expect(auth.signedIn, isFalse);
    expect(await store.readAccess('user-a'), isNull);
  });
  test('Cerrar sesión con cambios pendientes no descarta trabajo', () async {
    await auth.start();
    await store.enqueue(mutation('pending'));
    await auth.signOut();
    expect(auth.signedIn, isTrue);
    expect(await store.pendingForUser('user-a'), 1);
    expect(auth.error, contains('pendientes'));
  });
  test(
    'Cola separa usuarios y clínicas y conserva orden de inserción',
    () async {
      await store.enqueue(mutation('z'));
      await store.enqueue(mutation('a', version: 1));
      await store.enqueue(mutation('same', clinic: 'b'));
      await store.enqueue(mutation('same', user: 'user-b'));
      expect(
        (await store.queue(
          const SyncScope('user-a', 'a'),
        )).map((q) => q.mutation.id),
        ['z', 'a'],
      );
      await store.purgeUser('user-a');
      expect(await store.pendingForUser('user-a'), 0);
      expect(await store.pendingForUser('user-b'), 1);
    },
  );
  test('Reutilizar id con otro contenido se rechaza', () async {
    await store.enqueue(mutation('once'));
    await store.enqueue(mutation('once'));
    expect(await store.pendingForUser('user-a'), 1);
    await expectLater(
      store.enqueue(mutation('once', title: 'different')),
      throwsStateError,
    );
  });
  test(
    'Respuesta perdida se reintenta sin duplicar cambios y con espera creciente',
    () async {
      final gateway = DemoAdapter()..loseAcknowledgement = true;
      final engine = SyncEngine(store, FakeAuthority(), [
        gateway,
      ], now: () => now);
      await engine.enqueue(mutation('once'));
      await engine.synchronize(const SyncScope('user-a', 'a'));
      expect(gateway.version, 1);
      expect(
        (await store.queue(const SyncScope('user-a', 'a'))).single.state,
        QueueState.retry,
      );
      await engine.synchronize(const SyncScope('user-a', 'a'));
      expect(gateway.requests, 1);
      now = now.add(const Duration(seconds: 5));
      await engine.synchronize(const SyncScope('user-a', 'a'));
      expect(gateway.requests, 2);
      expect(gateway.version, 1);
      expect(await store.pendingForUser('user-a'), 0);
    },
  );
  test(
    'Conflicto conserva cambios y detiene operaciones posteriores del mismo registro',
    () async {
      final gateway = DemoAdapter()..forceConflict = true;
      final engine = SyncEngine(store, FakeAuthority(), [gateway]);
      await engine.enqueue(mutation('first'));
      await engine.enqueue(mutation('second', version: 1));
      await engine.synchronize(const SyncScope('user-a', 'a'));
      expect(gateway.requests, 1);
      final queue = await store.queue(const SyncScope('user-a', 'a'));
      expect(queue.first.state, QueueState.conflict);
      expect(queue.last.state, QueueState.pending);
    },
  );
  test(
    'Permiso revocado en servidor bloquea envío aunque la caché conserve rol',
    () async {
      final authority = FakeAuthority();
      final gateway = DemoAdapter();
      final engine = SyncEngine(store, authority, [gateway]);
      await engine.enqueue(mutation('pending'));
      authority.role = null;
      await engine.synchronize(const SyncScope('user-a', 'a'));
      expect(gateway.requests, 0);
      expect(
        (await store.queue(const SyncScope('user-a', 'a'))).single.state,
        QueueState.blocked,
      );
    },
  );
  test('Tipo no registrado y usuario ajeno no entran en la cola', () async {
    final engine = SyncEngine(store, FakeAuthority(), [DemoAdapter()]);
    await expectLater(
      engine.enqueue(mutation('bad', kind: 'staff_health')),
      throwsStateError,
    );
    await expectLater(
      engine.enqueue(mutation('bad', user: 'user-b')),
      throwsStateError,
    );
    expect(await store.pendingForUser('user-a'), 0);
  });
  test('Dos sincronizaciones simultáneas envían una sola vez', () async {
    final gateway = DemoAdapter();
    final engine = SyncEngine(store, FakeAuthority(), [gateway]);
    await engine.enqueue(mutation('once'));
    await Future.wait([
      engine.synchronize(const SyncScope('user-a', 'a')),
      engine.synchronize(const SyncScope('user-a', 'a')),
    ]);
    expect(gateway.requests, 1);
  });
  test(
    'La base nativa conserva caché y cola después de cerrar y reabrir',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vetdosis-offline-test-',
      );
      final file = '${directory.path}/offline.db';
      try {
        final first = LocalStore(await databaseFactoryIo.openDatabase(file));
        await first.writeAccess(MembershipSnapshot('user-a', [member], now));
        await first.enqueue(mutation('persistent'));
        await first.database.close();
        final second = LocalStore(await databaseFactoryIo.openDatabase(file));
        expect(
          (await second.readAccess('user-a'))!.members.single.clinicId,
          'a',
        );
        expect(await second.pendingForUser('user-a'), 1);
        await second.database.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
