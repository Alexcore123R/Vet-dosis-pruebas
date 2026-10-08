import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_models.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_repository.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_view_model.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_models.dart';
import 'package:vetdosis_pro/modules/forms/presentation/document_editor.dart';
import 'forms_test.dart' show FakeForms;

class ClinicalFake implements ClinicalRepository {
  bool fail = false;
  Completer<List<ClinicalCase>>? pending;
  @override
  Future<List<ClinicalCase>> cases(String clinicId, String? patientId) async {
    if (fail) throw Exception();
    if (pending != null) return pending!.future;
    return [
      ClinicalCase({
        'id': 'case',
        'patient_id': 'patient',
        'document_id': 'doc',
        'responsible_id': 'mvz',
        'kind': 'clinical_history',
        'title': 'Historia',
        'patient_name': 'Paciente',
        'created_at': '2026-10-07T01:00:00Z',
      }),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClinicalFormsFake extends FakeForms {
  @override
  Future<List<Map<String, dynamic>>> staff(String id) async => [];
}

void main() {
  final catalog =
      jsonDecode(
            File('assets/clinical/forms.clinical.v1.json').readAsStringSync(),
          )['templates']
          as List;
  test(
    'clinical schemas keep professional signature without tutor ID or prefilled measurements',
    () {
      for (final raw in catalog) {
        final s = validateTemplate(Map<String, dynamic>.from(raw));
        final fields = s['fields'] as List;
        expect(fields.any((f) => f['id'] == 'signer_id'), false);
        expect(
          fields.any((f) => f['id'] == 'signature' && f['locked'] == true),
          true,
        );
        expect(fields.any((f) => f.containsKey('default')), false);
        expect(
          () => validateValues(s, {'surgeon_id': 'not-a-uuid'}),
          raw['type'] == 'clinical_history'
              ? throwsFormatException
              : throwsFormatException,
        );
      }
    },
  );
  test(
    'UTC timestamps reject normalized invalid dates, missing zone and excessive precision',
    () {
      expect(clinicalInstant('2026-10-07T01:02:03.123456Z').isUtc, true);
      for (final value in [
        '2026-02-30T01:02:03Z',
        '2026-10-07T01:02:03',
        '2026-10-07T25:02:03Z',
        '2026-10-07T01:02:03.1234567Z',
      ]) {
        expect(() => clinicalInstant(value), throwsFormatException);
      }
    },
  );
  test(
    'measurements require exact values and matching units without medical defaults',
    () {
      final data = {
        'kind': 'weight',
        'value': '4,250',
        'unit': 'kg',
        'observed_at': '2026-10-07T01:02:03Z',
        'performed_by': 'mvz',
      };
      expect(validateObservation(data)['value'], '4.250');
      expect(
        () => validateObservation({...data, 'unit': 'mg'}),
        throwsFormatException,
      );
      expect(() => clinicalNumber('0', 'weight'), throwsFormatException);
      expect(() => clinicalNumber('1e4', 'fc'), throwsFormatException);
      expect(() => clinicalNumber('-1', 'fc'), throwsFormatException);
      expect(clinicalNumber('-1.5', 'temperature'), '-1.5');
    },
  );
  test(
    'loss of access clears chart and disposal ignores delayed sensitive response',
    () async {
      final repo = ClinicalFake(),
          vm = ClinicalViewModel(ClinicalFake(), 'clinic', null);
      await vm.load();
      expect(vm.cases, isNotEmpty);
      vm.dispose();
      final other = ClinicalViewModel(repo, 'clinic', null);
      await other.load();
      repo.fail = true;
      await other.load();
      expect(other.cases, isEmpty);
      expect(other.selected, isNull);
      repo.fail = false;
      repo.pending = Completer();
      final future = other.load();
      other.dispose();
      repo.pending!.complete([]);
      await future;
      expect(other.cases, isEmpty);
    },
  );
  testWidgets(
    'clinical editor displays only MVZ signature on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = Map<String, dynamic>.from(catalog.first);
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentEditor(
            repository: ClinicalFormsFake(),
            member: const ClinicMembership(
              clinicId: 'clinic',
              clinicName: 'Clínica',
              userId: 'mvz',
              role: ClinicRole.mvz,
            ),
            template: FormTemplateVersion(
              'version',
              'template',
              1,
              s,
              'clinic',
              'mvz',
              'base',
              true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Firma del tutor'), findsNothing);
      expect(find.text('Firma propia del MVZ responsable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
