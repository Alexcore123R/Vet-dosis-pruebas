import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_repository.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_forms.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_view_model.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_models.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_screen.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'prescribing_test.dart' show auxiliary, RxClinicalFake;
import 'medication_permissions_test.dart' show OperationalFake;
import 'forms_test.dart' show FakeForms;
import 'hospital_test.dart'
    show FakeHospital, FakeAlarms, alerts, member, stay, noon;

HospitalTask resolutionTask({int version = 1, bool allowed = true}) =>
    HospitalTask(
      id: 'med-task',
      stayId: 'stay-a',
      kind: 'medicacion',
      label: 'Synthetic medication',
      instructions: 'Synthetic indication',
      dueAt: noon,
      escalationMinutes: 15,
      state: HospitalTaskState.pending,
      version: version,
      actions: {'not_given': allowed, 'snooze': allowed, 'perform': false},
    );
HospitalDischargePreview preview() =>
    HospitalDischargePreview('stay-a', 1, List.filled(64, 'a').join(), [
      {
        'id': 'future',
        'version': 1,
        'label': 'Future synthetic indication',
        'instructions': 'Synthetic pending',
        'due_at': '2027-01-01T00:00:00Z',
      },
    ]);

class ResolutionFake extends FakeHospital
    implements HospitalResolutionRepository {
  int followups = 0, discharges = 0;
  @override
  Future<void> followup(
    String c,
    HospitalTask t,
    String action,
    int? minutes,
    String reason,
    String op,
  ) async {
    followups++;
  }

  @override
  Future<HospitalDischargePreview> dischargePreview(
    String c,
    HospitalStay s,
  ) async => preview();
  @override
  Future<void> confirmDischarge(
    String c,
    HospitalStay s,
    HospitalDischargePreview p,
    String reason,
    String op,
  ) async {
    discharges++;
  }
}

class ResolvedMedicationFake extends OperationalFake {
  @override
  Future<List<Map<String, dynamic>>> products() async => [
    {
      'id': 'product',
      'name': 'Synthetic',
      'presentation': 'Synthetic',
      'unit': 'ml',
    },
  ];
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    if (command == 'rx_hospital') return {'tasks': [], 'stays': []};
    if (command == 'rx_medications') return [];
    return super.read(command, args);
  }
}

class ResolutionClinicalFake extends RxClinicalFake {
  @override
  Future<List<ClinicalCase>> cases(String clinic, String? patient) async => [
    ClinicalCase({
      'id': 'case',
      'responsible_id': auxiliary.userId,
      'patient_id': 'patient',
      'document_id': 'document',
      'kind': 'clinical_history',
      'title': 'Synthetic case',
      'patient_name': 'Synthetic patient',
      'created_at': noon.toIso8601String(),
    }),
  ];
}

void main() {
  test('No-given data remains cancelled rather than an application', () {
    final t = HospitalTask.read({
      'id': 'm',
      'stay_id': 's',
      'kind': 'medicacion',
      'label': 'Synthetic',
      'instructions': 'Synthetic',
      'due_at': noon.toIso8601String(),
      'escalation_minutes': 15,
      'state': 'cancelled',
      'version': 2,
      'snooze_count': 0,
      'resolution_kind': 'not_given',
      'cancelled_by': 'reporter',
      'cancelled_at': noon.toIso8601String(),
      'cancel_reason': 'Synthetic absence',
    });
    expect(t.resolutionKind, 'not_given');
    expect(t.cancelledBy, 'reporter');
    expect(t.performedBy, isNull);
    expect(t.medicationRecordId, isNull);
    expect(t.urgency(noon), TaskUrgency.cancelled);
    expect(planHospitalAlarms([t], noon), isEmpty);
  });
  test(
    'Same-version refresh uses current rights; stale versions stay blocked',
    () async {
      final a = await alerts(FakeAlarms(supported: false));
      final repo = ResolutionFake();
      final old = resolutionTask();
      repo.snapshot = HospitalSnapshot([stay()], [old], permissions: const {});
      final vm = HospitalViewModel(repo, member(ClinicRole.auxiliar), a);
      await vm.refresh();
      expect(vm.canTask(old, 'not_given'), true);
      repo.snapshot = HospitalSnapshot(
        [stay()],
        [resolutionTask()],
        permissions: const {},
      );
      await vm.refresh();
      expect(vm.canTask(old, 'not_given'), true);
      repo.snapshot = HospitalSnapshot(
        [stay()],
        [resolutionTask(allowed: false)],
        permissions: const {},
      );
      await vm.refresh();
      expect(vm.canTask(old, 'not_given'), false);
      repo.snapshot = HospitalSnapshot(
        [stay()],
        [resolutionTask(version: 2)],
        permissions: const {},
      );
      await vm.refresh();
      expect(vm.canTask(old, 'not_given'), false);
      vm.dispose();
      a.dispose();
    },
  );
  test(
    'Followup and reviewed discharge never use generic perform or old discharge',
    () async {
      final a = await alerts(FakeAlarms(supported: false));
      final repo = ResolutionFake();
      final t = resolutionTask();
      repo.snapshot = HospitalSnapshot(
        [stay()],
        [t],
        medicationFollowup: true,
        reviewedDischarge: true,
        permissions: const {'hospital.discharge': true},
      );
      final vm = HospitalViewModel(repo, member(ClinicRole.auxiliar), a);
      await vm.refresh();
      expect(
        await vm.followup(
          t,
          'not_given',
          null,
          'Synthetic absence',
          'operation',
        ),
        true,
      );
      expect(repo.followups, 1);
      expect(repo.writes, 0);
      expect(
        await vm.confirmDischarge(
          stay(),
          preview(),
          'Synthetic reason',
          'operation',
        ),
        true,
      );
      expect(repo.discharges, 1);
      expect(repo.writes, 0);
      repo.fail = true;
      await vm.refresh();
      expect(
        await vm.followup(t, 'not_given', null, 'Synthetic', 'operation'),
        false,
      );
      vm.dispose();
      a.dispose();
    },
  );
  test('Discharge preview rejects missing content hash', () {
    expect(
      () => HospitalDischargePreview.read({
        'stay_id': 's',
        'version': 1,
        'pending': [],
        'pending_hash': 'bad',
      }),
      throwsFormatException,
    );
  });
  testWidgets(
    'No-given needs reason and review, blocks double tap and keeps retry key',
    (tester) async {
      final blocked = Completer<bool>();
      final operations = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HospitalResolutionForm(
            stay: stay(),
            task: resolutionTask(),
            action: HospitalResolutionAction.notGiven,
            save: (minutes, reason, operation) {
              expect(minutes, isNull);
              operations.add(operation);
              return operations.length == 1
                  ? blocked.future
                  : Future.value(false);
            },
          ),
        ),
      );
      expect(find.textContaining('Solo esta dosis'), findsOneWidget);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(operations, isEmpty);
      await tester.enterText(find.byType(TextField), 'Synthetic absence');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(operations.length, 1);
      blocked.complete(false);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(operations.length, 2);
      expect(operations[0], operations[1]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Snooze has no preset interval and does not save an unchosen interval',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HospitalResolutionForm(
            stay: stay(),
            task: resolutionTask(),
            action: HospitalResolutionAction.snooze,
            save: (m, r, o) async {
              calls++;
              return false;
            },
          ),
        ),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>),
            )
            .initialValue,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Synthetic delay');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Elige cuánto posponer el aviso.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Reviewed discharge displays future pending indications and requires review',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HospitalResolutionForm(
            stay: stay(),
            preview: preview(),
            action: HospitalResolutionAction.discharge,
            save: (m, r, o) async {
              calls++;
              return false;
            },
          ),
        ),
      );
      expect(find.text('Future synthetic indication'), findsOneWidget);
      expect(find.textContaining('1 indicaciones pendientes'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Synthetic reviewed reason',
      );
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'An initial task resolved while opening cannot become an unlinked application',
    (tester) async {
      final repo = ResolvedMedicationFake()
        ..permissions = {
          'schema_version': 1,
          'task_versions': true,
          'hospital.read': true,
          'scopes': [
            {'scope': 'cuidados', 'administer': true, 'draw': false},
          ],
        };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrescribingScreen(
              repository: repo,
              clinical: ResolutionClinicalFake(),
              forms: FakeForms(),
              member: auxiliary,
              initialCase: 'case',
              initialTask: 'resolved-task',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Reportar aplicación realizada'),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Reportar aplicación realizada'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RxEntryScreen), findsNothing);
      expect(
        find.textContaining('La dosis cambió o ya fue resuelta.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
