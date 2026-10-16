import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_repository.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_screen.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_view_model.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'clinical_screen_contract_test.dart'
    show ContractClinical, NoLegacyStaff, admin;

class IntakeFake extends ContractClinical
    implements ClinicalCaseRegistrationRepository {
  bool canRegister = true;
  int version = 1;
  bool hideRegistration = false;
  Completer<String>? pendingRegistration;
  final registrations = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> workspace(
    String clinicId,
    String? caseId,
  ) async {
    final result = (await super.workspace(clinicId, caseId))!;
    if (hideRegistration) {
      return result;
    }
    return {
      ...result,
      'registration_version': version,
      'actions': {...actions, 'create': canRegister},
      'patients': [
        {'id': 'patient', 'name': 'Paciente sintético'},
      ],
      'responsibles': [
        {'id': 'responsible', 'name': 'MVZ sintético', 'license': 'FICTICIA'},
      ],
    };
  }

  @override
  Future<String> registerCase(
    String clinicId,
    Map<String, dynamic> data,
    String operationId,
  ) async {
    registrations.add(data);
    return pendingRegistration == null
        ? 'case'
        : await pendingRegistration!.future;
  }
}

void main() {
  test(
    'registration capability requires explicit version and never falls back after loss',
    () async {
      final r = IntakeFake();
      final m = ClinicalViewModel(r, 'clinic', null);
      addTearDown(m.dispose);
      await m.load();
      expect(m.canCreate, isTrue);
      r.hideRegistration = true;
      await m.load();
      expect(m.canCreate, isFalse);
      expect(m.error, isNotNull);
      expect(m.cases, isEmpty);
      r.hideRegistration = false;
      r.version = 2;
      await m.load();
      expect(m.canCreate, isFalse);
      expect(m.error, isNotNull);
    },
  );
  testWidgets(
    'registration has explicit patient/responsible/date and no medical defaults',
    (t) async {
      final r = IntakeFake();
      await t.pumpWidget(
        MaterialApp(
          home: ClinicalScreen(
            repository: r,
            forms: NoLegacyStaff(),
            member: admin,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Registrar caso sin PDF'));
      await t.pumpAndSettle();
      final screen = t.widget<RxEntryScreen>(find.byType(RxEntryScreen));
      expect(screen.initial, isEmpty);
      expect(screen.fields.map((f) => f.key), [
        'patient_id',
        'responsible_id',
        'kind',
        'clinical_date',
        'reason',
        'notes',
      ]);
      expect(
        screen.fields.singleWhere((f) => f.key == 'clinical_date').type,
        'local_date',
      );
      expect(
        screen.fields.singleWhere((f) => f.key == 'notes').required,
        isFalse,
      );
      expect(find.text('Selecciona fecha'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Guardar'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(r.registrations, isEmpty);
    },
  );
  testWidgets(
    'missing registration permission hides create even for visual admin',
    (t) async {
      final r = IntakeFake()..canRegister = false;
      await t.pumpWidget(
        MaterialApp(
          home: ClinicalScreen(
            repository: r,
            forms: NoLegacyStaff(),
            member: admin,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Registrar caso sin PDF'), findsNothing);
    },
  );
  testWidgets(
    'date picker stores calendar date only after explicit selection',
    (t) async {
      Map<String, dynamic>? captured;
      await t.pumpWidget(
        MaterialApp(
          home: RxEntryScreen(
            title: 'Fecha',
            fields: const [
              RxField(
                'date',
                'Fecha clínica',
                type: 'local_date',
                required: true,
              ),
            ],
            submit: (d, _) async {
              captured = d;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Selecciona fecha'), findsOneWidget);
      await t.tap(find.byIcon(Icons.calendar_month));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(captured?['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    },
  );
  testWidgets('calendar validation rejects normalized invalid imported date', (
    t,
  ) async {
    int calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: RxEntryScreen(
          title: 'Fecha',
          fields: const [
            RxField(
              'date',
              'Fecha clínica',
              type: 'local_date',
              required: true,
            ),
          ],
          initial: const {'date': '2026-02-30'},
          submit: (_, _) async {
            calls++;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('Selecciona una fecha válida'), findsOneWidget);
  });
}
