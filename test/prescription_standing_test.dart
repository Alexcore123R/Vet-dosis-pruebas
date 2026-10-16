import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_view_model.dart';
import 'prescription_workflow_test.dart'
    show WorkflowFake, WorkflowCases, openRecipes;
import 'package:vetdosis_pro/modules/forms/domain/form_models.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_screen.dart';
import 'forms_test.dart' show FakeForms;
import 'prescribing_test.dart' show auxiliary;

class StandingFake extends WorkflowFake {
  StandingFake() {
    contract = {
      'schema_version': 1,
      'mode': 'individual_standing',
      'standing_version': 1,
      'can_prepare': true,
      'can_authorize': false,
      'recipes': [
        {
          'id': 'recipe',
          'revision': 1,
          'prepare_standing': true,
          'prepare': true,
        },
      ],
    };
  }
  @override
  Future<ReviewedPdf> pdf(String kind, String id) async {
    final bytes = Uint8List.fromList(utf8.encode('%PDF-SYNTHETIC'));
    return ReviewedPdf(bytes, sha256.convert(bytes).toString());
  }

  bool workspaceFails = false;
  Map<String, dynamic> workspace = {
    'members': <Map<String, dynamic>>[],
    'offers': [
      {
        'id': 'offer',
        'case_id': 'case',
        'created_by': 'responsible',
        'recipient_id': 'aux',
        'valid_until': '2026-10-17T12:00:00Z',
        'active': true,
        'available': true,
        'accepted': true,
        'revoked': false,
      },
    ],
    'events': <Map<String, dynamic>>[],
  };
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    if (command == 'rx_standing_workspace') {
      if (workspaceFails) throw StateError('offline');
      return workspace;
    }
    return super.read(command, args);
  }
}

Future<void> openStanding(WidgetTester tester, StandingFake repo) async {
  await openRecipes(tester, repo);
  await tester.tap(find.text('Recetas').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('A cargo').last);
  await tester.pumpAndSettle();
}

Future<void> openResponsible(WidgetTester tester, StandingFake repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  repo.contract!['can_authorize'] = true;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PrescribingScreen(
            repository: repo,
            clinical: WorkflowCases(),
            forms: FakeForms(),
            member: const ClinicMembership(
              clinicId: 'clinic',
              clinicName: 'Clínica',
              userId: 'responsible',
              role: ClinicRole.auxiliar,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Perfil').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('A cargo').last);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'standing needs typed contract and accepted case-specific scope; no role promotion',
    () async {
      final repo = StandingFake();
      final model = PrescribingViewModel(
        repo,
        WorkflowCases(),
        auxiliary,
        null,
      );
      addTearDown(model.dispose);
      await model.load();
      expect(model.standingAvailable, isTrue);
      expect(model.standingFor(repo.row).single['id'], 'offer');
      expect(model.standingFor({...repo.row, 'case_id': 'other'}), isEmpty);
      expect(model.canOfferStanding, isFalse);
      expect(model.prescriptionAction(repo.row, 'prepare_standing'), isTrue);
      repo.workspaceFails = true;
      await model.refreshStanding();
      expect(model.standingOffers, isEmpty);
      expect(model.prescriptionAction(repo.row, 'prepare_standing'), isFalse);
      repo.workspaceFails = false;
      await model.refreshStanding();
      expect(model.prescriptionAction(repo.row, 'prepare_standing'), isTrue);
      repo.contract!['mode'] = 'individual';
      await model.load();
      expect(model.error, isNotNull);
      expect(model.standingOffers, isEmpty);
      expect(model.prescriptionAction(repo.row, 'prepare'), isFalse);
    },
  );

  test('unknown standing version fails closed', () async {
    final repo = StandingFake();
    repo.contract!['standing_version'] = 2;
    final model = PrescribingViewModel(repo, WorkflowCases(), auxiliary, null);
    addTearDown(model.dispose);
    await model.load();
    expect(model.error, isNotNull);
    expect(model.standingAvailable, isFalse);
    expect(model.standingOffers, isEmpty);
  });

  testWidgets(
    'recipient explicitly selects standing authorization; no implicit first offer',
    (tester) async {
      final repo = StandingFake();
      await openRecipes(tester, repo);
      final button = find.text('Preparar con autorización temporal');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final save = find.text('Preparar bajo autorización previa');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      final selects = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(selects.first);
      await tester.tap(selects.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vence 2026-10-17T12:00:00Z').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(selects.last);
      await tester.tap(selects.last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Persona · firma registrada').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Persona');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.writes.single['command'], 'rx_prepare_standing');
      expect(repo.writes.single['p_delegation'], 'offer');
      expect(repo.writes.single['p_attestation'], 'attestation');
      expect(repo.writes.single.containsKey('p_shared_signature'), isFalse);
    },
  );

  testWidgets(
    'acceptance is explicit and does not mark any prescription reviewed',
    (tester) async {
      final repo = StandingFake();
      final offer =
          (repo.workspace['offers'] as List).single as Map<String, dynamic>;
      offer['accepted'] = false;
      offer['active'] = false;
      await openStanding(tester, repo);
      await tester.ensureVisible(find.text('Aceptar'));
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      final save = find.text('Aceptar autorización');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.writes.single['command'], 'rx_standing_accept');
      expect(repo.writes.single['p_confirmed'], isTrue);
      expect(repo.writes.single['p_id'], 'offer');
    },
  );

  testWidgets(
    'viewing inbox never marks a post review and shows delivery limitation',
    (tester) async {
      final repo = StandingFake();
      repo.workspace['events'] = [
        {
          'id': 'event',
          'prescription_id': 'recipe',
          'patient_name': 'Paciente ficticio',
          'recipient_id': 'aux',
          'created_at': 'fecha',
          'reviewed': false,
        },
      ];
      await openStanding(tester, repo);
      expect(
        find.textContaining('no son notificaciones con la app cerrada'),
        findsOneWidget,
      );
      expect(find.text('Revisiones pendientes: 1'), findsOneWidget);
      expect(repo.writes, isEmpty);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
    },
  );
  testWidgets(
    'leaving in charge requires selected case, person, expiry and explicit confirmation',
    (tester) async {
      final repo = StandingFake();
      repo.workspace['members'] = [
        {'id': 'aux', 'label': 'Persona'},
      ];
      await openResponsible(tester, repo);
      final offer = find.text('Dejar a cargo');
      await tester.ensureVisible(offer);
      await tester.tap(offer);
      await tester.pumpAndSettle();
      expect(find.text('Selecciona fecha y hora local'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      final save = find.text('Ofrecer autorización');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      expect(find.textContaining('La persona deberá aceptar'), findsOneWidget);
    },
  );

  testWidgets(
    'resuming needs a reason and sends one scoped operation, no clinical grants',
    (tester) async {
      final repo = StandingFake();
      await openResponsible(tester, repo);
      final resume = find.text('Retomar revisión');
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Retomar revisión');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      await tester.enterText(
        find.byType(TextFormField),
        'Regresé a revisión individual',
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.writes.single['command'], 'rx_standing_resume');
      expect(repo.writes.single['p_clinic'], 'clinic');
      expect(repo.writes.single['p_reason'], 'Regresé a revisión individual');
    },
  );

  testWidgets('post review cannot confirm a PDF with a different hash', (
    tester,
  ) async {
    final repo = StandingFake();
    repo.row['state'] = 'issued';
    repo.workspace['events'] = [
      {
        'id': 'event',
        'prescription_id': 'recipe',
        'patient_name': 'Paciente ficticio',
        'recipient_id': 'aux',
        'created_at': 'fecha',
        'reviewed': false,
        'pdf_hash': 'expected',
        'content_hash': 'content',
      },
    ];
    await openResponsible(tester, repo);
    final review = find.text('Revisar');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Registrar revisión posterior'), findsNothing);
    expect(
      find.textContaining('El PDF o la versión no coincide'),
      findsOneWidget,
    );
    expect(repo.writes, isEmpty);
  });
}
