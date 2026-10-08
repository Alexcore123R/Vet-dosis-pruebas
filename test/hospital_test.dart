import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_repository.dart';
import 'package:vetdosis_pro/modules/hospital/application/hospital_alerts.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_view_model.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_screen.dart';
import 'patients_test.dart' show FakePatients;

final noon = DateTime.utc(2026, 10, 7, 12);
HospitalTask task({
  String id = 'task-a',
  DateTime? due,
  DateTime? snooze,
  HospitalTaskState state = HospitalTaskState.pending,
  int version = 1,
}) => HospitalTask(
  id: id,
  stayId: 'stay-a',
  kind: 'medicacion',
  label: 'Tratamiento ficticio',
  instructions: 'Caso de prueba, sin uso clínico',
  dueAt: due ?? noon,
  escalationMinutes: 10,
  state: state,
  version: version,
  snoozedUntil: snooze,
  performedBy: state == HospitalTaskState.done ? 'actor-servidor' : null,
  performedAt: state == HospitalTaskState.done ? noon : null,
);
HospitalStay stay() => HospitalStay(
  id: 'stay-a',
  clinicId: 'a',
  patientId: 'patient-a',
  patientName: 'Paciente ficticio hospitalizado',
  species: 'Ficticia',
  cage: 'Box 1',
  admittedAt: noon,
  version: 1,
);
ClinicMembership member(ClinicRole role) => ClinicMembership(
  clinicId: 'a',
  clinicName: 'Clínica ficticia',
  userId: 'user-a',
  role: role,
);

class FakeAlarms implements AlarmBackend {
  FakeAlarms({this.supported = true});
  @override
  final bool supported;
  @override
  String get timingNotice => 'Solo prueba de planificación';
  final scheduled = <int, AlarmJob>{};
  final cancelled = <int>[];
  int writes = 0, permissions = 0;
  String permissionResult = 'Activados: ejemplo ficticio';
  Completer<void>? pending;
  @override
  Future<void> initialize() async {}
  @override
  Future<String> requestPermission() async {
    permissions++;
    return permissionResult;
  }

  @override
  Future<void> schedule(int id, AlarmJob job) async {
    writes++;
    if (pending != null) await pending!.future;
    scheduled[id] = job;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }
}

class FakeHospital implements HospitalRepository {
  HospitalSnapshot snapshot = HospitalSnapshot([stay()], [task()]);
  bool fail = false;
  int writes = 0, reads = 0;
  Completer<HospitalSnapshot>? pending;
  @override
  Future<HospitalSnapshot> load(String clinicId) async {
    reads++;
    if (fail) throw StateError('network');
    return pending == null ? snapshot : pending!.future;
  }

  @override
  Future<void> admit(
    String clinicId,
    String patientId,
    String cage,
    String operationId,
  ) async {
    writes++;
  }

  @override
  Future<void> prescribe(
    String clinicId,
    String stayId,
    String kind,
    String label,
    String instructions,
    List<DateTime> times,
    int delay,
    String op,
  ) async {
    writes++;
  }

  @override
  Future<void> perform(String clinicId, HospitalTask t) async {
    writes++;
    snapshot = HospitalSnapshot(snapshot.stays, [
      task(state: HospitalTaskState.done, version: 2),
    ]);
  }

  @override
  Future<void> snooze(
    String clinicId,
    HospitalTask t,
    int minutes,
    String reason,
  ) async {
    writes++;
  }

  @override
  Future<void> cancel(String clinicId, HospitalTask t, String reason) async {
    writes++;
  }

  @override
  Future<void> discharge(
    String clinicId,
    HospitalStay stay,
    String reason,
  ) async {
    writes++;
  }
}

Future<HospitalAlerts> alerts(
  FakeAlarms backend, {
  DateTime Function()? now,
}) async {
  SharedPreferences.setMockInitialValues({});
  final a = HospitalAlerts(
    backend,
    await SharedPreferences.getInstance(),
    now: now ?? () => noon,
  );
  await a.initialize();
  await a.bind('user-a:a:mvz');
  return a;
}

void main() {
  test(
    'Horario original, límite exacto de retraso y posposición no equivalen a administración',
    () {
      expect(
        task().urgency(noon.subtract(const Duration(seconds: 1))),
        TaskUrgency.scheduled,
      );
      expect(task().urgency(noon), TaskUrgency.due);
      expect(
        task().urgency(noon.add(const Duration(minutes: 10))),
        TaskUrgency.escalated,
      );
      expect(
        task(snooze: noon.add(const Duration(minutes: 5))).urgency(noon),
        TaskUrgency.snoozed,
      );
      final snoozed = task(snooze: noon.add(const Duration(minutes: 20)));
      expect(
        snoozed.urgency(noon.add(const Duration(minutes: 10))),
        TaskUrgency.escalated,
      );
      expect(snoozed.dueAt, noon);
      expect(snoozed.state, HospitalTaskState.pending);
    },
  );
  test(
    'Plan UTC conserva minutos, respeta posposición y elimina terminados',
    () {
      final due = noon.add(const Duration(minutes: 1, seconds: 30));
      final jobs = planHospitalAlarms([task(due: due)], noon);
      expect(jobs.map((j) => j.at), [
        due,
        due.add(const Duration(minutes: 10)),
      ]);
      final snoozed = planHospitalAlarms([
        task(snooze: noon.add(const Duration(minutes: 15))),
      ], noon);
      expect(snoozed.length, 1);
      expect(snoozed.single.at, noon.add(const Duration(minutes: 15)));
      expect(snoozed.single.escalated, true);
      expect(
        planHospitalAlarms([
          task(state: HospitalTaskState.done),
          task(state: HospitalTaskState.cancelled),
        ], noon),
        isEmpty,
      );
    },
  );
  test(
    'Muchos retrasos producen un aviso genérico agrupado; presupuesto nativo 60',
    () {
      final past = List.generate(
        100,
        (i) =>
            task(id: 'past-$i', due: noon.subtract(const Duration(hours: 1))),
      );
      final jobs = planHospitalAlarms(past, noon);
      expect(jobs.length, 1);
      expect(jobs.single.summary, true);
      final future = List.generate(
        100,
        (i) => task(
          id: 'future-$i',
          due: noon.add(Duration(minutes: i + 1)),
        ),
      );
      expect(planHospitalAlarms([...past, ...future], noon).length, 60);
    },
  );
  test(
    'Horas futuras obligatorias, duplicados de un mismo instante rechazados',
    () {
      expect(() => validateSchedule([], now: noon), throwsFormatException);
      expect(() => validateSchedule([noon], now: noon), throwsFormatException);
      final later = noon.add(const Duration(hours: 1));
      expect(
        () => validateSchedule([later, later.toLocal()], now: noon),
        throwsFormatException,
      );
      expect(
        validateSchedule([
          later.add(const Duration(hours: 1)),
          later,
        ], now: noon),
        [later, later.add(const Duration(hours: 1))],
      );
    },
  );
  test(
    'Activación explícita; IDs sin duplicación, terminados cancelan avisos',
    () async {
      final backend = FakeAlarms();
      final a = await alerts(backend);
      final tasks = [task(due: noon.add(const Duration(hours: 1)))];
      await a.reconcile('user-a:a:mvz', tasks);
      expect(backend.writes, 0);
      expect(backend.permissions, 0);
      await a.enable();
      await a.reconcile('user-a:a:mvz', tasks);
      final ids = backend.scheduled.keys.toList();
      expect(ids.length, 2);
      await a.reconcile('user-a:a:mvz', tasks);
      expect(backend.writes, 2);
      expect(backend.scheduled.keys.toList(), ids);
      await a.reconcile('user-a:a:mvz', [task(state: HospitalTaskState.done)]);
      expect(backend.scheduled, isEmpty);
      expect(backend.cancelled, containsAll(ids));
      a.dispose();
    },
  );
  test(
    'Plan de clínica ajena no programa; cambio de sesión cancela avisos propios',
    () async {
      final backend = FakeAlarms();
      final a = await alerts(backend);
      await a.enable();
      await a.reconcile('another-clinic', [
        task(due: noon.add(const Duration(hours: 1))),
      ]);
      expect(backend.writes, 0);
      await a.reconcile('user-a:a:mvz', [
        task(due: noon.add(const Duration(hours: 1))),
      ]);
      await a.bind(null);
      expect(backend.scheduled, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'hospital.alert.ids.v1',
        ),
        '{}',
      );
      a.dispose();
    },
  );
  test(
    'Cambio de sesión durante programación cancela lo ya programado y detiene lo restante',
    () async {
      final backend = FakeAlarms()..pending = Completer<void>();
      final a = await alerts(backend);
      await a.enable();
      final scheduling = a.reconcile('user-a:a:mvz', [
        task(due: noon.add(const Duration(hours: 1))),
      ]);
      await Future<void>.delayed(Duration.zero);
      final binding = a.bind(null);
      backend.pending!.complete();
      await scheduling;
      await binding;
      expect(backend.scheduled, isEmpty);
      expect(backend.writes, 1);
      a.dispose();
    },
  );
  test(
    'Los retrasos agrupados no vuelven a sonar en cada actualización',
    () async {
      var now = noon;
      final backend = FakeAlarms();
      final a = await alerts(backend, now: () => now);
      await a.enable();
      final old = [task(due: noon.subtract(const Duration(hours: 1)))];
      await a.reconcile('user-a:a:mvz', old);
      now = noon.add(const Duration(minutes: 1));
      await a.reconcile('user-a:a:mvz', old);
      expect(backend.writes, 1);
      a.dispose();
    },
  );
  test(
    'Web no solicita permisos nativos ni presume alarmas con navegador cerrado',
    () async {
      final backend = FakeAlarms(supported: false);
      final a = await alerts(backend);
      await a.enable();
      expect(a.enabled, false);
      expect(backend.permissions, 0);
      expect(a.status, contains('Cerrar el navegador'));
      a.dispose();
    },
  );
  test(
    'Auxiliar confirma pero no prescribe/da alta; recepción no lee hoja',
    () async {
      final a = await alerts(FakeAlarms(supported: false));
      final repo = FakeHospital();
      final aux = HospitalViewModel(
        repo,
        member(ClinicRole.auxiliar),
        a,
        now: () => noon,
      );
      await aux.refresh();
      expect(await aux.discharge(stay(), 'Motivo ficticio'), false);
      expect(repo.writes, 0);
      await aux.perform(task());
      expect(repo.writes, 1);
      expect(aux.snapshot.tasks.single.performedBy, 'actor-servidor');
      aux.dispose();
      final reception = HospitalViewModel(
        repo,
        member(ClinicRole.recepcion),
        a,
      );
      final before = repo.reads;
      await reception.refresh();
      expect(repo.reads, before);
      reception.dispose();
      a.dispose();
    },
  );
  test(
    'Fallo de lectura borra hoja y respuesta tardía no repone datos tras cerrar',
    () async {
      final a = await alerts(FakeAlarms(supported: false));
      final repo = FakeHospital();
      final vm = HospitalViewModel(repo, member(ClinicRole.mvz), a);
      await vm.refresh();
      repo.fail = true;
      await vm.refresh();
      expect(vm.snapshot.tasks, isEmpty);
      expect(vm.snapshot.stays, isEmpty);
      vm.dispose();
      final slow = FakeHospital()..pending = Completer<HospitalSnapshot>();
      final old = HospitalViewModel(slow, member(ClinicRole.mvz), a);
      final loading = old.refresh();
      old.dispose();
      slow.pending!.complete(HospitalSnapshot([stay()], [task()]));
      await loading;
      expect(old.snapshot.tasks, isEmpty);
      a.dispose();
    },
  );
  testWidgets(
    'Hoja móvil muestra quién/cuándo y tabla permite desplazamiento horizontal',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = await alerts(FakeAlarms(supported: false));
      final repo = FakeHospital()
        ..snapshot = HospitalSnapshot(
          [stay()],
          [task(due: DateTime.now(), state: HospitalTaskState.done)],
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                HospitalScreen(
                  repository: repo,
                  patients: FakePatients(),
                  member: member(ClinicRole.auxiliar),
                  alerts: a,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('actor-servidor'), findsOneWidget);
      expect(find.text('Ingresar paciente'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Paciente × hora'));
      await tester.pumpAndSettle();
      expect(find.byType(Table), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  test(
    'Permiso denegado cancela avisos anteriores y metadatos no contienen datos clínicos',
    () async {
      final backend = FakeAlarms();
      final a = await alerts(backend);
      await a.enable();
      await a.reconcile('user-a:a:mvz', [
        task(due: noon.add(const Duration(hours: 1))),
      ]);
      final preferences = await SharedPreferences.getInstance();
      final metadata = preferences.getString('hospital.alert.ids.v1')!;
      expect(metadata, isNot(contains('Tratamiento ficticio')));
      expect(metadata, isNot(contains('Caso de prueba')));
      expect(metadata, isNot(contains('Paciente ficticio')));
      backend.permissionResult = 'Permiso denegado.';
      await a.enable();
      expect(a.enabled, false);
      expect(backend.scheduled, isEmpty);
      expect(a.status, 'Permiso denegado.');
      a.dispose();
    },
  );
}
