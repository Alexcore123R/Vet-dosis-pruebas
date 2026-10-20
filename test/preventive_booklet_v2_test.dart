import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/patients/application/preventive_model.dart';
import 'package:vetdosis_pro/modules/patients/application/preventive_pdf.dart';
import 'package:vetdosis_pro/modules/patients/domain/preventive_repository.dart';
import 'package:vetdosis_pro/modules/patients/domain/preventive_coverage.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import 'package:vetdosis_pro/modules/patients/presentation/preventive_screen.dart';

Map<String, dynamic> bookletData() => {
  'schema_version': 2,
  'clinic_id': 'c',
  'patient_id': 'p',
  'patient_name': 'Paciente sintético',
  'species': 'Felino',
  'can_attach': true,
  'can_confirm': true,
  'can_schedule': true,
  'events': [
    {
      'id': 'e',
      'kind': 'preventive',
      'created_at': '2026-10-20T12:00:00Z',
      'created_by': 'INTERNAL_STAFF',
      'payload': {
        'date': '2026-10-20',
        'preventive_version': 1,
        'type': 'vacuna',
        'date_precision': 'unknown',
        'origin': 'owner_report',
        'informant': 'PRIVATE_INFORMANT',
        'coverage': 'Triple referida, componentes desconocidos',
        'product': 'No especificado',
        'notes': 'INTERNAL_NOTE',
        'next_date': '2030-01-01',
        'next_date_by': 'UNCONFIRMED_NAME',
      },
    },
  ],
  'evidence': [
    {
      'id': 'f',
      'event_id': 'e',
      'label': 'Comprobante sintético',
      'mime': 'application/pdf',
      'size': 1024,
    },
  ],
  'plans': [
    {
      'id': 'plan',
      'type': 'vacuna',
      'coverage': 'Rabia',
      'due_date': '2030-02-01',
      'reason': 'INTERNAL_REASON',
    },
    {
      'id': 'retired',
      'type': 'vacuna',
      'coverage': 'RETIRED_PLAN',
      'due_date': '2030-03-01',
    },
  ],
  'retired': ['retired'],
  'links': [],
  'members': [
    {'user_id': 'u', 'display_name': 'MVZ sintético'},
  ],
};

class BookletFake implements PreventiveRepository {
  Map<String, dynamic> data = bookletData();
  bool fail = false;
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic>? planned;
  @override
  Future<Map<String, dynamic>> booklet(String c, String p) async {
    if (fail) throw StateError('revoked');
    return pending?.future ?? data;
  }

  @override
  Future<void> attachEvidence(
    String c,
    String p,
    String e,
    String label,
    Uint8List b,
    String m,
    String op,
  ) async {}
  @override
  Future<Uint8List> evidence(String c, String p, String id) async =>
      Uint8List(0);
  @override
  Future<void> planPreventive(
    String c,
    String p,
    Map<String, dynamic> d,
    String op,
  ) async {
    planned = d;
  }

  @override
  Future<void> retirePlan(
    String c,
    String p,
    String id,
    String reason,
    String op,
  ) async {}
  @override
  Future<void> schedulePreventive(
    String c,
    String p,
    String id,
    Map<String, dynamic> d,
    String op,
  ) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Coverage round-trips without inferring anything from triple or sextuple',
    () {
      final raw = <String, dynamic>{
        'date': '2026-10-20',
        'type': 'vacuna',
        'preventive_version': 1,
        'origin': 'owner_report',
        'date_precision': 'unknown',
        'informant': 'Tutor',
        'product': '',
        'coverage_version': 1,
        'coverage_components': ['feline_calicivirus', 'feline_panleukopenia'],
        'coverage_other': 'Otra cobertura indicada',
      };
      final result = validateEvent(EventKind.preventive, raw);
      expect(result['coverage_components'], [
        'feline_calicivirus',
        'feline_panleukopenia',
      ]);
      expect(result['coverage'], contains('Panleucopenia felina'));
      expect(validateEvent(EventKind.preventive, result), result);
      expect(coverageText([], 'Séxtuple'), 'Séxtuple');
      expect(
        () => validateCoverage(['rabies', 'rabies']),
        throwsFormatException,
      );
      expect(() => validateCoverage(['invented']), throwsFormatException);
    },
  );
  test(
    'Evidence is bounded and identified by bytes rather than a filename',
    () {
      expect(
        evidenceMime(Uint8List.fromList(utf8.encode('%PDF-1.4'))),
        'application/pdf',
      );
      expect(
        evidenceMime(Uint8List.fromList([255, 216, 255, 224])),
        'image/jpeg',
      );
      expect(
        () => evidenceMime(Uint8List.fromList(utf8.encode('<svg>'))),
        throwsFormatException,
      );
      expect(
        () => evidenceMime(Uint8List(maxPreventiveEvidence + 1)),
        throwsFormatException,
      );
    },
  );
  test(
    'Sharing omits private notes, sources, files and unconfirmed historical next dates',
    () async {
      final data = bookletData();
      final lines = bookletShareLines(data).join('\n');
      for (final private in [
        'PRIVATE_INFORMANT',
        'INTERNAL_STAFF',
        'INTERNAL_NOTE',
        'INTERNAL_REASON',
        '2030-01-01',
        'RETIRED_PLAN',
        'Comprobante sintético',
      ]) {
        expect(lines, isNot(contains(private)));
      }
      expect(lines, contains('Referida por el propietario'));
      expect(lines, contains('Fecha de aplicación desconocida'));
      expect(lines, contains('2030-02-01'));
      final pdf = await preventivePdf(data, 'Clínica sintética');
      expect(utf8.decode(pdf.take(5).toList()), '%PDF-');
      expect(pdf.length, greaterThan(1000));
    },
  );
  test(
    'A cleared or failed snapshot cannot restore cached clinical records',
    () async {
      final repo = BookletFake();
      final model = PreventiveModel(repo, 'c', 'p');
      await model.load();
      expect(model.data, isNotNull);
      repo.pending = Completer();
      final request = model.load();
      model.clear();
      repo.pending!.complete(repo.data);
      await request;
      expect(model.data, isNull);
      repo.pending = null;
      repo.data = {...repo.data, 'patient_id': 'other'};
      await model.load();
      expect(model.data, isNull);
      expect(model.error, isNotNull);
      model.dispose();
    },
  );
  testWidgets(
    'Read-only carnet has no write controls; permission loss clears it',
    (tester) async {
      final repo = BookletFake()
        ..data = {
          ...bookletData(),
          'can_attach': false,
          'can_confirm': false,
          'can_schedule': false,
        };
      await tester.pumpWidget(
        MaterialApp(
          home: PreventiveScreen(
            repository: repo,
            clinic: 'c',
            patient: 'p',
            clinicName: 'Clínica',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Paciente sintético'), findsOneWidget);
      expect(find.text('Indicar próxima aplicación'), findsNothing);
      expect(find.text('Agendar cita'), findsNothing);
      expect(find.textContaining('Adjuntar foto'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.textContaining('Paciente sintético'), findsNothing);
      repo.fail = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Paciente sintético'), findsNothing);
      expect(find.textContaining('No se pudo comprobar'), findsOneWidget);
    },
  );
  testWidgets(
    'Carnet keeps origin visible with large text on 320px in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: PreventiveScreen(
                repository: BookletFake(),
                clinic: 'c',
                patient: 'p',
                clinicName: 'Clínica',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('Referida por el propietario'),
          500,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Referida por el propietario'),
          findsOneWidget,
        );
        expect(find.text('RETIRED_PLAN'), findsNothing);
      }
    },
  );
}
