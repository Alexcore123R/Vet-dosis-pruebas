import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_models.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_repository.dart';
import 'package:vetdosis_pro/modules/forms/presentation/form_view_model.dart';
import 'package:vetdosis_pro/modules/forms/presentation/document_flow_screen.dart';
import 'form_document_drafts_test.dart' show DraftRepo;
import 'form_template_permissions_test.dart' show stylist;

class WorkflowRepo extends DraftRepo implements FormWorkflowRepository {
  WorkflowRepo() {
    workspace!['mode'] = 'individual_forms';
    workspace!['flow_version'] = 1;
  }
  bool deny = false;
  final actions = <String, bool>{
    for (final k in [
      'edit',
      'select',
      'sign_attention',
      'submit',
      'authorize',
      'preview',
      'capture_tutor',
      'view_pdf',
      'issue',
      'reopen',
      'reject',
    ])
      k: false,
  };
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> documentFlow(String id) async {
    if (deny) {
      throw StateError('access_lost');
    }
    return {
      'schema_version': 1,
      'mode': 'individual_forms',
      'document': {
        'id': 'draft',
        'state': 'draft',
        'revision': 1,
        'version_id': 'approved',
        'responsible_id': 'professional',
        'values': {'mvz_name': 'MVZ ficticio', 'mvz_license': 'FICTICIA'},
        'snapshot': row.snapshot,
      },
      'actions': actions,
      'people': [
        {'id': 'actual', 'name': 'Persona real'},
      ],
      'cases': [],
      'responsibles': [
        {'id': 'professional', 'name': 'MVZ ficticio'},
      ],
      'field_choices': {},
    };
  }

  @override
  Future<void> flowAction(String action, Map<String, dynamic> arguments) async {
    calls.add({'action': action, ...arguments});
  }

  @override
  Future<ReviewedPdf> tutorPreview(String id) async =>
      throw StateError('not_expected');
}

void main() {
  test(
    'known individual workflow cannot fall back to old mode or unknown version',
    () async {
      final r = WorkflowRepo();
      final model = FormViewModel(r, stylist);
      addTearDown(model.dispose);
      await model.load();
      expect(model.individualFlow, isTrue);
      expect(model.error, isNull);
      r.workspace!['flow_version'] = 2;
      await model.load();
      expect(model.error, isNotNull);
      expect(model.documents, isEmpty);
      r.workspace!['flow_version'] = 1;
      await model.load();
      expect(model.individualFlow, isTrue);
      r.workspace!['mode'] = 'draft_authorship';
      await model.load();
      expect(model.error, isNotNull);
    },
  );
  test(
    'new contract requires workflow repository, never legacy role fallback',
    () async {
      final r = DraftRepo();
      r.workspace!['mode'] = 'individual_forms';
      r.workspace!['flow_version'] = 1;
      final m = FormViewModel(r, stylist);
      addTearDown(m.dispose);
      await m.load();
      expect(m.error, isNotNull);
      expect(m.documents, isEmpty);
    },
  );
  testWidgets(
    'preparer sees only current server actions, no borrowed signature or authority',
    (t) async {
      final r = WorkflowRepo();
      r.actions['select'] = true;
      await t.pumpWidget(
        MaterialApp(
          home: DocumentFlowScreen(
            repository: r,
            id: 'draft',
            edit: (_, _) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Seleccionar persona y caso'), findsOneWidget);
      expect(find.text('Autorizar esta versión'), findsNothing);
      expect(find.text('Revisar PDF y emitir'), findsNothing);
      expect(find.text('Usar firma del MVZ'), findsNothing);
      await t.tap(find.text('Seleccionar persona y caso'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Guardar'));
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(r.calls, isEmpty);
      expect(find.textContaining('Completa Persona'), findsOneWidget);
    },
  );
  testWidgets(
    'authorization checkbox starts unchecked and cannot submit implicitly',
    (t) async {
      final r = WorkflowRepo();
      r.actions['authorize'] = true;
      await t.pumpWidget(
        MaterialApp(
          home: DocumentFlowScreen(
            repository: r,
            id: 'draft',
            edit: (_, _) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Autorizar esta versión'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Autorizar esta versión'));
      await t.pumpAndSettle();
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await t.ensureVisible(find.text('Guardar'));
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(r.calls, isEmpty);
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Guardar'));
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(r.calls.single['action'], 'form_authorize_individual');
      expect(r.calls.single['p_confirmed'], isTrue);
      expect(r.calls.single['p_revision'], 1);
    },
  );
  testWidgets('access loss removes previously enabled actions', (t) async {
    final r = WorkflowRepo();
    r.actions['sign_attention'] = true;
    await t.pumpWidget(
      MaterialApp(
        home: DocumentFlowScreen(
          repository: r,
          id: 'draft',
          edit: (_, _) async {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Firmar mi atención / explicación'), findsOneWidget);
    r.deny = true;
    await t.tap(find.byIcon(Icons.refresh));
    await t.pumpAndSettle();
    expect(find.text('Firmar mi atención / explicación'), findsNothing);
    expect(find.textContaining('No se pudo verificar'), findsOneWidget);
  });
}
