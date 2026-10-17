import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_models.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_repository.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_view_model.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_screen.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'package:vetdosis_pro/modules/forms/presentation/form_view_model.dart';
import 'form_document_drafts_test.dart' show DraftRepo;
import 'form_template_permissions_test.dart' show stylist;
import 'clinical_test.dart' show ClinicalFake, ClinicalFormsFake;

class ContractClinical extends ClinicalFake
    implements ClinicalPermissionRepository {
  bool missing = false, denied = false;
  int schemaVersion = 1, reads = 0;
  final actions = {
    for (final k in [
      'observe',
      'act',
      'correct',
      'authorize',
      'revoke',
      'bind',
    ])
      k: false,
  };
  final actScopes = <String>[];
  List<Map<String, dynamic>> documents = [];
  final writes = <Map<String, dynamic>>[];
  final c = ClinicalCase({
    'id': 'case',
    'patient_id': 'patient',
    'document_id': 'legacy',
    'responsible_id': 'responsible',
    'kind': 'clinical_history',
    'title': 'Historia',
    'patient_name': 'Paciente',
    'created_at': '2026-10-07T00:00:00Z',
  });
  @override
  Future<Map<String, dynamic>?> workspace(
    String clinicId,
    String? caseId,
  ) async => missing
      ? null
      : {
          'schema_version': schemaVersion,
          'mode': 'explicit_clinical',
          'clinic_id': clinicId,
          'case_id': caseId,
          'can_read': !denied,
          'actions': actions,
          'act_scopes': actScopes,
          'documents': documents,
          'bindings': [],
          'members': [],
          'procedures': [],
        };
  @override
  Future<List<ClinicalCase>> cases(String clinicId, String? patientId) async {
    reads++;
    return [c];
  }

  @override
  Future<ClinicalBundle> bundle(String caseId) async =>
      ClinicalBundle(c, [], [], [], [], []);
  @override
  Future<void> observation(
    String caseId,
    Map<String, dynamic> data,
    String operationId,
  ) async {
    writes.add(data);
  }

  @override
  Future<void> bindScope(
    String caseId,
    String scope,
    String procedure,
    bool professional,
    String source,
    String reason,
  ) async {}
}

class NoLegacyStaff extends ClinicalFormsFake {
  int legacyStaffReads = 0;
  @override
  Future<List<Map<String, dynamic>>> staff(String id) async {
    legacyStaffReads++;
    throw StateError('legacy_staff_closed');
  }
}

const admin = ClinicMembership(
  clinicId: 'clinic',
  clinicName: 'Synthetic',
  userId: 'current-person',
  role: ClinicRole.admin,
);
void main() {
  test(
    'clinical navigation follows explicit read access rather than visual job',
    () async {
      final r = DraftRepo();
      final view = FormViewModel(r, stylist);
      addTearDown(view.dispose);
      await view.load();
      expect(view.canOpenClinical, isTrue);
      r.workspace = null;
      await view.load();
      expect(view.canOpenClinical, isFalse);
    },
  );

  test('denied workspace never reads clinical rows', () async {
    final r = ContractClinical()..denied = true;
    final model = ClinicalViewModel(r, 'clinic', null);
    addTearDown(model.dispose);
    await model.load();
    expect(r.reads, 0);
    expect(model.cases, isEmpty);
    expect(model.permissionsKnown, isTrue);
  });
  test(
    'known contract loss and unknown version clear prior data and capabilities',
    () async {
      final r = ContractClinical()..actions['observe'] = true;
      final model = ClinicalViewModel(r, 'clinic', null);
      addTearDown(model.dispose);
      await model.load(caseId: 'case');
      expect(model.can('observe'), isTrue);
      r.missing = true;
      await model.load(caseId: 'case');
      expect(model.selected, isNull);
      expect(model.workspace, isNull);
      expect(model.error, isNotNull);
      expect(model.can('observe'), isFalse);
      r.missing = false;
      r.schemaVersion = 2;
      await model.load(caseId: 'case');
      expect(model.error, isNotNull);
      expect(model.cases, isEmpty);
    },
  );
  testWidgets(
    'visual admin with explicit observation permission can append without staff-role lookup',
    (t) async {
      final r = ContractClinical()..actions['observe'] = true,
          forms = NoLegacyStaff();
      await t.pumpWidget(
        MaterialApp(
          home: ClinicalScreen(repository: r, forms: forms, member: admin),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Paciente · Historia'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Anexar medición'));
      await t.tap(find.text('Anexar medición'));
      await t.pumpAndSettle();
      expect(forms.legacyStaffReads, 0);
      expect(find.text('Quién realizó'), findsNothing);
      final entry = t.widget<RxEntryScreen>(find.byType(RxEntryScreen));
      expect(entry.initial, isEmpty);
      expect(
        entry.fields.map((f) => f.key),
        containsAll(['kind', 'value', 'at', 'notes']),
      );
      expect(entry.fields.any((f) => f.key == 'person'), isFalse);
      expect(
        entry.fields.singleWhere((f) => f.key == 'notes').required,
        isFalse,
      );
      await entry.submit({
        'kind': 'fc',
        'value': '99',
        'at': '2026-10-16T00:00:00Z',
        'notes': '',
        'performed_by': 'another-person',
      }, 'synthetic-op');
      expect(r.writes.single['performed_by'], 'current-person');
      expect(r.writes.single.containsKey('temperature'), isFalse);
      expect(r.writes.single.containsKey('weight'), isFalse);
    },
  );
  testWidgets(
    'read-only case hides clinical actions and does not offer unsigned original',
    (t) async {
      final r = ContractClinical();
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
      await t.tap(find.text('Paciente · Historia'));
      await t.pumpAndSettle();
      expect(find.text('Anexar medición'), findsNothing);
      expect(find.text('Anexar actuación'), findsNothing);
      expect(find.text('Autorizar persona y procedimiento'), findsNothing);
      expect(find.text('Ver PDF original firmado'), findsNothing);
    },
  );
  testWidgets(
    'signed linked document appears separately from legacy original',
    (t) async {
      final r = ContractClinical()
        ..documents = [
          {
            'id': 'linked',
            'title': 'Hoja enfocada',
            'state': 'signed',
            'revision': 1,
            'is_original': false,
          },
        ];
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
      await t.tap(find.text('Paciente · Historia'));
      await t.pumpAndSettle();
      expect(find.text('Documento firmado · Hoja enfocada'), findsOneWidget);
      expect(find.text('Ver PDF original firmado'), findsNothing);
    },
  );
}
