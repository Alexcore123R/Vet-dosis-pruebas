import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_models.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_repository.dart';
import 'package:vetdosis_pro/modules/forms/presentation/form_view_model.dart';
import 'package:vetdosis_pro/modules/forms/presentation/document_editor.dart';

Map<String, dynamic> schema(String type) => Map<String, dynamic>.from(
  (jsonDecode(
            File(
              'assets/clinical/${type.startsWith('clinical_') || type.startsWith('surgical_') ? 'forms.clinical.v1.json' : 'forms.reference.v1.json'}',
            ).readAsStringSync(),
          )['templates']
          as List)
      .firstWhere((t) => t['type'] == type),
);
const member = ClinicMembership(
  clinicId: 'clinic',
  clinicName: 'Clínica ficticia',
  userId: 'mvz',
  role: ClinicRole.mvz,
);
FormDocument document() =>
    FormDocument('doc', 'draft', 1, 'version', 'mvz', {}, {
      'schema': schema('general'),
      'patient': {'name': 'Paciente', 'species': 'Ficticia'},
      'owner': {'name': 'Tutor'},
    }, null);

class FakeForms implements FormRepository {
  bool fail = false;
  final items = <FormDocument>[document()];
  @override
  Future<List<FormTemplateVersion>> templates(String clinicId) async {
    if (fail) throw Exception('network');
    return [];
  }

  @override
  Future<List<FormDocument>> documents(String clinicId) async {
    if (fail) throw Exception('network');
    return items;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'base schemas contain protected fields and euthanasia requirements without death before signing',
    () {
      for (final type in formTypes.keys) {
        expect(() => validateTemplate(schema(type)), returnsNormally);
      }
      final e = schema('euthanasia');
      final ids = (e['fields'] as List).map((f) => f['id']).toSet();
      expect(
        ids.containsAll({
          'clinical_reason',
          'prior_opinion',
          'method',
          'body_disposition',
          'cost',
        }),
        isTrue,
      );
      expect(ids.contains('death_confirmed'), isFalse);
    },
  );
  test(
    'cannot remove protected fields, revoke revocation or add irrevocable text',
    () {
      final s = schema('general');
      (s['fields'] as List).removeWhere((f) => f['id'] == 'signer_id');
      expect(() => validateTemplate(s), throwsFormatException);
      final r = schema('general');
      (r['clauses'] as List).removeWhere((c) => c['id'] == 'revocation');
      expect(() => validateTemplate(r), throwsFormatException);
      final t = schema('general');
      t['clauses'][0]['text'] = 'Autorización irrevocable';
      expect(() => validateTemplate(t), throwsFormatException);
    },
  );
  test(
    'typed values reject unknown fields and malformed numbers, dates, selections, tables',
    () {
      final s = schema('general');
      s['fields'].addAll([
        {
          'id': 'extra_number',
          'label': 'Número',
          'type': 'number',
          'required': false,
          'locked': false,
        },
        {
          'id': 'extra_date',
          'label': 'Fecha',
          'type': 'date',
          'required': false,
          'locked': false,
        },
        {
          'id': 'extra_select',
          'label': 'Selección',
          'type': 'single',
          'options': ['A', 'B'],
          'required': false,
          'locked': false,
        },
        {
          'id': 'extra_table',
          'label': 'Tabla',
          'type': 'table',
          'columns': ['Dato', 'Valor'],
          'required': false,
          'locked': false,
        },
      ]);
      expect(
        () => validateValues(s, {
          'extra_number': '1.25',
          'extra_date': '2026-02-28',
          'extra_select': 'A',
          'extra_table': [
            ['Dato', 'Valor'],
          ],
        }),
        returnsNormally,
      );
      for (final values in [
        {'patient': 'Otra identidad'},
        {'unknown': 'x'},
        {'extra_number': 'NaN'},
        {'extra_date': '2026-02-30'},
        {'extra_select': 'C'},
        {
          'extra_table': [
            ['Dato'],
          ],
        },
      ]) {
        expect(() => validateValues(s, values), throwsFormatException);
      }
    },
  );
  test(
    'privacy link and identification are explicit, required; no identification photo field',
    () {
      final s = schema('general');
      expect(
        () => validateValues(s, {}, complete: true),
        throwsFormatException,
      );
      expect(
        () => validateValues(s, {'privacy_url': 'http://example.test'}),
        throwsFormatException,
      );
      expect(
        () => validateValues(s, {
          'signer_id': 'NUMERO-FICTICIO',
          'privacy_url': 'https://example.test/aviso',
        }),
        returnsNormally,
      );
      expect(
        (s['fields'] as List).any((f) => f['id'] == 'identification_photo'),
        isFalse,
      );
    },
  );
  test('reviewed PDF rejects corrupted bytes and wrong hash', () {
    final bytes = Uint8List.fromList(utf8.encode('%PDF-SYNTHETIC-TEST'));
    final hash = sha256.convert(bytes).toString();
    expect(() => ReviewedPdf(bytes, hash), returnsNormally);
    expect(() => ReviewedPdf(bytes, 'wrong'), throwsFormatException);
    expect(
      () => ReviewedPdf(Uint8List.fromList(utf8.encode('not PDF')), hash),
      throwsFormatException,
    );
  });
  test('changing document invalidates file review and acceptance', () {
    final session = PdfReviewSession();
    session.setDocument(document());
    final bytes = Uint8List.fromList(utf8.encode('%PDF-SYNTHETIC-TEST'));
    session.setPdf(ReviewedPdf(bytes, sha256.convert(bytes).toString()));
    expect(session.canFinalize, isFalse);
    session.accepted = true;
    expect(session.canFinalize, isTrue);
    session.invalidate();
    expect(session.canFinalize, isFalse);
  });
  test(
    'pasante uses auxiliar permissions; admin does not implicitly become MVZ',
    () {
      expect(ClinicRole.values.map((r) => r.name), isNot(contains('pasante')));
      expect(const FormsAccess(ClinicRole.auxiliar).finalize, isFalse);
      expect(const FormsAccess(ClinicRole.admin).finalize, isFalse);
      expect(const FormsAccess(ClinicRole.mvz).finalize, isTrue);
    },
  );
  test('failed read clears sensitive data and disposal releases it', () async {
    final repo = FakeForms(), vm = FormViewModel(FakeForms(), member);
    final actual = FormViewModel(repo, member);
    await actual.load();
    expect(actual.documents, isNotEmpty);
    repo.fail = true;
    await actual.load();
    expect(actual.documents, isEmpty);
    expect(actual.error, isNotNull);
    actual.dispose();
    vm.dispose();
  });
  testWidgets(
    'phone editor shows own signatures and number-only identification without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentEditor(
            repository: FakeForms(),
            member: member,
            document: document(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('solo número, sin foto'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Firma propia del MVZ responsable'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Firma propia del MVZ responsable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'auxiliary draft has no preparation action or professional signature',
    (tester) async {
      const auxiliary = ClinicMembership(
        clinicId: 'clinic',
        clinicName: 'Clínica ficticia',
        userId: 'aux',
        role: ClinicRole.auxiliar,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentEditor(
            repository: FakeForms(),
            member: auxiliary,
            document: document(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Preparar PDF con firmas para revisar'), findsNothing);
      expect(find.text('Firma propia del MVZ responsable'), findsNothing);
    },
  );
}
