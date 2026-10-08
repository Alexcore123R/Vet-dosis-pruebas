import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_repository.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_models.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_models.dart';
import 'package:vetdosis_pro/modules/prescribing/domain/prescribing_models.dart';
import 'package:vetdosis_pro/modules/prescribing/domain/prescribing_repository.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_screen.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_view_model.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'forms_test.dart' show FakeForms;

class RxFake implements PrescribingRepository {
  bool fail = false;
  Completer<dynamic>? pending;
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    if (fail) throw Exception();
    if (pending != null) return pending!.future;
    if (command == 'rx_profiles') {
      return [
        {
          'id': 'profile',
          'user_id': 'aux',
          'name': 'Persona',
          'license': 'CEDULA CAPTURADA',
          'version': 1,
          'has_signature': false,
          'authorized': false,
        },
      ];
    }
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> products() async => [];
  @override
  Future<dynamic> write(String command, Map<String, dynamic> args) async =>
      null;
  @override
  Future<ReviewedPdf> pdf(String kind, String id) async =>
      throw UnimplementedError();
}

class RxClinicalFake implements ClinicalRepository {
  @override
  Future<List<ClinicalCase>> cases(String clinicId, String? patientId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const auxiliary = ClinicMembership(
  clinicId: 'clinic',
  clinicName: 'Clínica',
  userId: 'aux',
  role: ClinicRole.auxiliar,
);
void main() {
  test(
    'exact application quantity rejects zero, exponent, separators and excess precision',
    () {
      expect(exactMedicationQuantity('1,250'), '1.250');
      for (final s in ['0', '-1', '1e6', '1,000,000', '0.1234567891']) {
        expect(() => exactMedicationQuantity(s), throwsFormatException);
      }
    },
  );
  test('CSV encodes exact text and neutralizes spreadsheet formulas', () {
    for (final s in ['=1+1', '+cmd', '-cmd', '@cmd', '\t=cmd', '  =cmd']) {
      expect(csvCell(s), startsWith('"\''));
    }
    expect(csvCell('a"b\nfoo'), '"a""b\nfoo"');
  });
  test(
    'report export preserves reference/incomplete state and pending IDs without invented folio',
    () {
      final text = reportCsv({
        'official': false,
        'complete': false,
        'starts_at': '2026-01-01T00:00:00Z',
        'ends_at': '2026-02-01T00:00:00Z',
        'cutoff': '2026-02-01T00:00:01Z',
        'pending_ids': ['pending'],
        'snapshot': {
          'entries': [
            {
              'patient_name': 'Paciente',
              'name': '=PRODUCT',
              'quantity': '1.250',
              'unit': 'ml',
              'official_folio': null,
            },
          ],
        },
      });
      expect(text, contains('NO OFICIAL'));
      expect(text, contains('INCOMPLETO'));
      expect(text, contains('pending'));
      expect(text, contains('1.250'));
      expect(text, contains("'=PRODUCT"));
      expect(text, contains('"Folio capturado"'));
    },
  );
  test('reporting and validation states remain distinguishable', () {
    expect(medicationState({}), contains('pendiente'));
    expect(
      medicationState({
        'review': {'decision': 'validada'},
      }),
      'Validada por el MVZ',
    );
    expect(
      medicationState({
        'review': {'decision': 'validada'},
        'superseded': true,
      }),
      contains('Sustituida'),
    );
    expect(
      medicationState({'incidence': 'Saldo insuficiente'}),
      contains('Incidencia'),
    );
  });
  test(
    'profile declaration alone grants no professional authority and failure clears data',
    () async {
      final repo = RxFake();
      final vm = PrescribingViewModel(repo, RxClinicalFake(), auxiliary, null);
      await vm.load();
      expect(vm.ownProfile, isNotNull);
      expect(vm.professional, false);
      repo.fail = true;
      await vm.load();
      expect(vm.profiles, isEmpty);
      expect(vm.medications, isEmpty);
      expect(vm.error, isNotNull);
      vm.dispose();
    },
  );
  test('disposed models discard a delayed sensitive result', () async {
    final repo = RxFake()..pending = Completer();
    final vm = PrescribingViewModel(repo, RxClinicalFake(), auxiliary, null);
    final load = vm.load();
    vm.dispose();
    repo.pending!.complete([]);
    await load;
    expect(vm.profiles, isEmpty);
  });
  testWidgets(
    'auxiliary profile screen has no professional grant or controlled report actions on phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PrescribingScreen(
                repository: RxFake(),
                clinical: RxClinicalFake(),
                forms: FakeForms(),
                member: auxiliary,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('pendiente o no vigente'), findsOneWidget);
      expect(
        find.text('Compartir datos, firma o permisos ordinarios'),
        findsNothing,
      );
      expect(find.text('Crear corte del periodo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'invalid time prevents submission rather than silently substituting device time',
    (tester) async {
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: RxEntryScreen(
            title: 'Aplicación',
            fields: const [
              RxField('observed', 'Hora', type: 'instant', required: true),
            ],
            submit: (_, _) async {
              submitted = true;
            },
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField),
        '2026-02-30T00:00:00Z',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(submitted, false);
      expect(find.text('Fecha y hora inválidas.'), findsOneWidget);
    },
  );
}
