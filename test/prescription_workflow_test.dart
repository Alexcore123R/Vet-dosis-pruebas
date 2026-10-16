import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/prescribing/domain/prescribing_repository.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_screen.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_view_model.dart';
import 'package:vetdosis_pro/modules/patients/presentation/signature_pad.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_models.dart';
import 'prescribing_test.dart' show RxFake, auxiliary;
import 'medication_permissions_test.dart' show CaseFake;
import 'forms_test.dart' show FakeForms;

class WorkflowFake extends RxFake implements PrescriptionPermissionRepository {
  Map<String, dynamic> row = {
    'id': 'recipe',
    'case_id': 'case',
    'revision': 1,
    'state': 'draft',
    'patient_name': 'Paciente ficticio',
    'controlled': false,
    'official_folio': '',
    'responsible_id': 'responsible',
  };
  Map<String, dynamic>? contract = {
    'schema_version': 1,
    'mode': 'individual',
    'can_prepare': true,
    'recipes': [
      {
        'id': 'recipe',
        'revision': 1,
        'sign': true,
        'prepare': true,
        'edit': true,
      },
    ],
  };
  final writes = <Map<String, dynamic>>[];
  final reads = <String>[];
  Completer<void>? writing;
  @override
  Future<Map<String, dynamic>?> prescriptionPermissions(String clinic) async =>
      contract;
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    reads.add(command);
    if (this.fail) throw StateError('outage');
    if (command == 'rx_list') return [Map<String, dynamic>.from(row)];
    if (command == 'rx_consultations') {
      return [
        {
          'id': 'attestation',
          'name': 'Persona',
          'signed_at': 'fecha sintética',
        },
      ];
    }
    if (command == 'rx_snapshot') {
      return {
        ...row,
        'instructions': 'Cuidados ficticios',
        'items': [
          {
            'product_name': 'Producto ficticio',
            'presentation': 'Presentación ficticia',
            'quantity': '1',
            'unit': 'ml',
            'route': 'Vía ficticia',
            'interval_text': 'Intervalo ficticio',
            'duration_text': 'Duración ficticia',
            'care': 'Nota ficticia',
          },
        ],
      };
    }
    return super.read(command, args);
  }

  @override
  Future<dynamic> write(String command, Map<String, dynamic> args) async {
    writes.add({'command': command, ...args});
    await writing?.future;
    return 'synthetic-result';
  }
}

class WorkflowCases extends CaseFake {
  @override
  Future<List<ClinicalCase>> cases(String clinic, String? patient) async => [
    ClinicalCase({
      'id': 'case',
      'responsible_id': 'responsible',
      'patient_name': 'Paciente ficticio',
      'title': 'Consulta ficticia',
    }),
  ];
}

Future<void> openRecipes(WidgetTester tester, WorkflowFake repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PrescribingScreen(
            repository: repo,
            clinical: WorkflowCases(),
            forms: FakeForms(),
            member: auxiliary,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Perfil').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Recetas').last);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'explicit prescription rights do not request legacy role-based reports for reception',
    () async {
      final repo = WorkflowFake();
      const member = ClinicMembership(
        clinicId: 'clinic',
        clinicName: 'Clínica',
        userId: 'aux',
        role: ClinicRole.recepcion,
      );
      final model = PrescribingViewModel(repo, CaseFake(), member, null);
      await model.load();
      expect(model.error, isNull);
      expect(
        model.prescriptionAction(model.prescriptions.single, 'prepare'),
        true,
      );
      expect(repo.reads, isNot(contains('rx_reports')));
      model.dispose();
    },
  );
  test(
    'recipe actions use current server revision and fail closed on contract loss',
    () async {
      final repo = WorkflowFake();
      final model = PrescribingViewModel(repo, CaseFake(), auxiliary, null);
      await model.load();
      final oldRow = model.prescriptions.single;
      expect(model.prescriptionAction(oldRow, 'sign'), true);
      expect(model.prescriptionAction(oldRow, 'authorize'), false);
      repo.row = {...repo.row, 'revision': 2};
      await model.load();
      expect(model.prescriptionAction(oldRow, 'sign'), false);
      repo.contract = null;
      await model.load();
      expect(model.error, isNotNull);
      expect(model.prescriptionKnown, true);
      expect(model.canPreparePrescription, false);
      expect(model.prescriptionAction(oldRow, 'sign'), false);
      model.dispose();
    },
  );
  test('unknown workflow version cannot revive legacy preparation', () async {
    final repo = WorkflowFake()..contract = {'schema_version': 2};
    final model = PrescribingViewModel(repo, CaseFake(), auxiliary, null);
    await model.load();
    expect(model.error, isNotNull);
    expect(model.prescriptionKnown, true);
    expect(model.canPreparePrescription, false);
    model.dispose();
  });
  testWidgets(
    'consultation signer must draw and explicitly confirm; no signing for another account',
    (tester) async {
      final repo = WorkflowFake()..writing = Completer<void>();
      await openRecipes(tester, repo);
      await tester.ensureVisible(find.text('Firmar consulta realizada'));
      await tester.tap(find.text('Firmar consulta realizada'));
      await tester.pumpAndSettle();
      expect(
        find.text('Usar firma del titular solo con permiso vigente'),
        findsNothing,
      );
      await tester.tap(find.text('Registrar mi firma'));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      final pad = find.descendant(
        of: find.byType(SignaturePad),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.onPanStart != null,
        ),
      );
      await tester.drag(pad, const Offset(70, 25));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar mi firma'));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Registrar mi firma'));
      await tester.tap(find.text('Registrar mi firma'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(repo.writes, hasLength(1));
      expect(repo.writes.single['command'], 'rx_consultation_sign');
      expect(repo.writes.single['p_name'], 'Persona');
      expect(repo.writes.single['p_confirmed'], true);
      expect(repo.writes.single.containsKey('p_signer'), false);
      expect(repo.writes.single.containsKey('p_user'), false);
      expect(repo.writes.single['p_signature'], isNotEmpty);
      repo.writing!.complete();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'preparing selects a recorded consultation and sends no shared signature',
    (tester) async {
      final repo = WorkflowFake();
      await openRecipes(tester, repo);
      await tester.ensureVisible(find.text('Preparar para autorización'));
      await tester.tap(find.text('Preparar para autorización'));
      await tester.pumpAndSettle();
      expect(find.byType(SignaturePad), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Persona · firma registrada').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar para autorización'));
      await tester.pumpAndSettle();
      expect(repo.writes.single['command'], 'rx_prepare_attributed');
      expect(repo.writes.single['p_attestation'], 'attestation');
      expect(repo.writes.single.containsKey('p_shared_signature'), false);
      expect(repo.writes.single.containsKey('p_signature'), false);
    },
  );
  testWidgets(
    'individual authorizer sees the exact captured indications before confirming',
    (tester) async {
      final repo = WorkflowFake();
      repo.row = {
        ...repo.row,
        'revision': 2,
        'state': 'awaiting_authorization',
      };
      repo.contract = {
        'schema_version': 1,
        'mode': 'individual',
        'can_prepare': false,
        'recipes': [
          {'id': 'recipe', 'revision': 2, 'authorize': true},
        ],
      };
      await openRecipes(tester, repo);
      expect(
        find.textContaining('Pendiente de autorización del MVZ'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Revisar y autorizar indicaciones'));
      await tester.tap(find.text('Revisar y autorizar indicaciones'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Intervalo ficticio'), findsOneWidget);
      expect(find.textContaining('Cuidados ficticios'), findsOneWidget);
      await tester.ensureVisible(find.text('Autorizar y preparar PDF'));
      await tester.tap(find.text('Autorizar y preparar PDF'));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Autorizar y preparar PDF'));
      await tester.pumpAndSettle();
      expect(repo.writes.single['command'], 'rx_authorize_individual');
      expect(repo.writes.single['p_revision'], 2);
      expect(repo.writes.single['p_confirmed'], true);
    },
  );
}
