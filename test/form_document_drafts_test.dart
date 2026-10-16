import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_models.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_repository.dart';
import 'package:vetdosis_pro/modules/forms/presentation/form_view_model.dart';
import 'package:vetdosis_pro/modules/forms/presentation/document_editor.dart';
import 'form_template_permissions_test.dart' show TemplateRepo, stylist;
import 'forms_test.dart' show schema;

class DraftRepo extends TemplateRepo implements FormDraftRepository {
  Map<String, dynamic>? workspace = {
    'schema_version': 1,
    'mode': 'draft_authorship',
    'can_read': true,
    'can_prepare': true,
    'responsibles': [
      {'id': 'professional', 'name': 'MVZ ficticio', 'license': 'FICTICIA'},
    ],
    'approved_template_ids': ['approved'],
  };
  FormDocument row = FormDocument(
    'draft',
    'draft',
    1,
    'approved',
    'professional',
    {},
    {
      'schema': schema('general'),
      'patient': {'name': 'Paciente ficticio'},
      'owner': {'name': 'Tutor ficticio'},
      'document_flow_version': 1,
      'can_edit': true,
    },
    null,
  );
  int legacyCreates = 0, signs = 0;
  String? signedName;
  List<List<double>?>? signedPoints;
  Completer<void>? signing;
  @override
  Future<Map<String, dynamic>?> documentWorkspace(String clinicId) async =>
      workspace;
  @override
  Future<List<FormDocument>> documents(String clinicId) async => [row];
  @override
  Future<FormDocument> createAttributedDraft(
    String clinicId,
    String patientId,
    String versionId,
    String responsibleId,
    Map<String, dynamic> values,
    Map<String, dynamic> branding,
    String operationId,
  ) async => row;
  @override
  Future<void> signAuthorship(
    String id,
    int revision,
    String name,
    List<List<double>?> signature,
    bool confirmed,
    String operationId,
  ) async {
    signs++;
    signedName = name;
    signedPoints = signature;
    expect(confirmed, isTrue);
    expect(id, 'draft');
    expect(revision, 1);
    if (signing != null) await signing!.future;
  }

  @override
  Future<FormDocument> createDocument(
    String clinicId,
    String patientId,
    String versionId,
    Map<String, dynamic> values,
    Map<String, dynamic> branding,
    String operationId,
  ) async {
    legacyCreates++;
    throw StateError('legacy unavailable');
  }
}

void main() {
  test(
    'explicit draft workspace enables approved templates without granting authorization',
    () async {
      final repo = DraftRepo();
      final model = FormViewModel(repo, stylist);
      addTearDown(model.dispose);
      await model.load();
      expect(model.error, isNull);
      expect(model.documentsKnown, isTrue);
      expect(model.documents, isNotEmpty);
      final approved = FormTemplateVersion(
        'approved',
        't',
        2,
        schema('general'),
        'clinic',
        'other',
        'base',
        true,
      );
      final old = FormTemplateVersion(
        'legacy',
        't',
        1,
        schema('general'),
        'clinic',
        'other',
        'base',
        true,
      );
      expect(model.canCreateDraft(approved), isTrue);
      expect(model.canCreateDraft(old), isFalse);
      expect(model.documentResponsibles.single['id'], 'professional');
      repo.workspace = null;
      await model.load();
      expect(model.error, isNotNull);
      expect(model.documents, isEmpty);
      expect(model.canCreateDraft(approved), isFalse);
    },
  );
  test(
    'unknown/malformed draft workspace clears prior documents and never falls back to job',
    () async {
      final repo = DraftRepo();
      final model = FormViewModel(repo, stylist);
      addTearDown(model.dispose);
      await model.load();
      repo.workspace = {...repo.workspace!, 'mode': 'unknown'};
      await model.load();
      expect(model.documents, isEmpty);
      expect(model.error, isNotNull);
      expect(model.documentResponsibles, isEmpty);
    },
  );
  testWidgets(
    'draft authorship never offers borrowed MVZ/tutor signatures or PDF issuance',
    (tester) async {
      final repo = DraftRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentEditor(
            repository: repo,
            member: stylist,
            document: repo.row,
            draftOnly: true,
            draftResponsibles: const [
              {
                'id': 'professional',
                'name': 'MVZ ficticio',
                'license': 'FICTICIA',
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Usar firma del titular con permiso vigente'),
        findsNothing,
      );
      expect(find.text('Firma propia del MVZ responsable'), findsNothing);
      expect(find.text('Preparar PDF con firmas para revisar'), findsNothing);
      final save = find.text('Guardar firma de elaboración');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.signs, 0);
      expect(
        find.text(
          'Escribe tu nombre, dibuja tu firma y confirma la elaboración.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'authorship uses drawn own signature and blocks repeated submission',
    (tester) async {
      final repo = DraftRepo()..signing = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentEditor(
            repository: repo,
            member: stylist,
            document: repo.row,
            draftOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final name = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == 'Tu nombre completo',
      );
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Persona ficticia');
      final canvas = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onPanStart != null,
      );
      await tester.ensureVisible(canvas);
      await tester.drag(canvas, const Offset(80, 25));
      await tester.pump();
      final confirmed = find.widgetWithText(
        CheckboxListTile,
        'Confirmo que elaboré y revisé esta versión con mi propia identidad y firma.',
      );
      await tester.ensureVisible(confirmed);
      await tester.tap(confirmed);
      await tester.pump();
      final save = find.text('Guardar firma de elaboración');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save);
      await tester.pump();
      expect(repo.signs, 1);
      expect(repo.signedName, 'Persona ficticia');
      expect(repo.signedPoints, isNotEmpty);
      expect(repo.legacyCreates, 0);
      repo.signing!.complete();
      await tester.pumpAndSettle();
    },
  );
}
