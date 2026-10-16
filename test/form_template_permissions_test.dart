import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/core/domain/navigation_access.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_models.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_repository.dart';
import 'package:vetdosis_pro/modules/forms/presentation/form_view_model.dart';
import 'package:vetdosis_pro/modules/forms/presentation/template_editor.dart';
import 'forms_test.dart' show FakeForms, schema;

const stylist = ClinicMembership(
  clinicId: 'clinic',
  clinicName: 'Synthetic clinic',
  userId: 'person',
  role: ClinicRole.estilista,
);

class TemplateRepo extends FakeForms
    implements FormTemplatePermissionRepository {
  Map<String, dynamic>? contract = {
    'schema_version': 1,
    'mode': 'templates_only',
    'can_read': true,
    'can_edit': true,
    'can_approve': false,
    'can_brand': false,
  };
  int documentReads = 0, templateReads = 0;
  @override
  Future<Map<String, dynamic>?> templatePermissions(String clinicId) async =>
      contract;
  @override
  Future<List<FormTemplateVersion>> templates(String clinicId) async {
    templateReads++;
    if (this.fail) throw StateError('outage');
    return [
      FormTemplateVersion(
        'base',
        'template',
        1,
        schema('general'),
        null,
        null,
        null,
        false,
      ),
    ];
  }

  @override
  Future<List<FormDocument>> documents(String clinicId) async {
    documentReads++;
    return super.documents(clinicId);
  }
}

void main() {
  test(
    'template grant overrides visual job and never reads patient documents',
    () async {
      final repo = TemplateRepo();
      final model = FormViewModel(repo, stylist);
      addTearDown(model.dispose);
      await model.load();
      expect(navigationAllowed('Formatos', stylist), isTrue);
      expect(model.error, isNull);
      expect(model.canEditTemplates, isTrue);
      expect(model.canApproveTemplates, isFalse);
      expect(model.canBrand, isFalse);
      expect(model.templates, isNotEmpty);
      expect(model.documentsAvailable, isFalse);
      expect(repo.documentReads, 0);
      repo.contract!['can_edit'] = false;
      repo.contract!['can_brand'] = true;
      await model.load();
      expect(model.canEditTemplates, isFalse);
      expect(model.canBrand, isTrue);
    },
  );
  test(
    'missing known contract and malformed capabilities clear previous schemas',
    () async {
      for (final bad in [
        null,
        {
          'schema_version': 2,
          'mode': 'templates_only',
          'can_read': true,
          'can_edit': true,
          'can_approve': true,
          'can_brand': true,
        },
        {
          'schema_version': 1,
          'mode': 'templates_only',
          'can_read': true,
          'can_edit': 'true',
          'can_approve': true,
          'can_brand': true,
        },
      ]) {
        final repo = TemplateRepo();
        final model = FormViewModel(repo, stylist);
        await model.load();
        repo.contract = bad;
        await model.load();
        expect(model.error, isNotNull);
        expect(model.templates, isEmpty);
        expect(model.canEditTemplates, isFalse);
        expect(model.canApproveTemplates, isFalse);
        expect(repo.documentReads, 0);
        model.dispose();
      }
    },
  );
  test(
    'revoked read does not request schemas; failed reload clears permissions',
    () async {
      final repo = TemplateRepo();
      final model = FormViewModel(repo, stylist);
      addTearDown(model.dispose);
      await model.load();
      repo.contract = {
        ...repo.contract!,
        'can_read': false,
        'can_edit': false,
        'can_approve': false,
        'can_brand': false,
      };
      await model.load();
      expect(repo.templateReads, 1);
      expect(model.templates, isEmpty);
      repo.contract!['can_read'] = true;
      repo.fail = true;
      await model.load();
      expect(model.error, isNotNull);
      expect(model.canBrand, isFalse);
    },
  );
  testWidgets(
    'template editor disables approval when only editing is authorized',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TemplateEditor(
            repository: TemplateRepo(),
            clinicId: 'clinic',
            original: FormTemplateVersion(
              'base',
              'template',
              1,
              schema('general'),
              null,
              null,
              null,
              false,
            ),
            canApprove: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile).last,
      );
      expect(checkbox.onChanged, isNull);
      expect(checkbox.value, isFalse);
    },
  );
}
