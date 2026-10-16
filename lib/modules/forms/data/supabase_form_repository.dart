import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/form_models.dart';
import '../domain/form_repository.dart';

class SupabaseFormRepository
    implements
        FormRepository,
        FormTemplatePermissionRepository,
        FormDraftRepository {
  SupabaseFormRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>?> documentWorkspace(String clinicId) async {
    try {
      return Map<String, dynamic>.from(
        await rpc('form_document_workspace', {'p_clinic': clinicId}) as Map,
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  @override
  Future<FormDocument> createAttributedDraft(
    String clinicId,
    String patientId,
    String versionId,
    String responsibleId,
    Map<String, dynamic> values,
    Map<String, dynamic> branding,
    String operationId,
  ) async => FormDocument.read(
    Map<String, dynamic>.from(
      await rpc('form_document_draft_create', {
        'p_clinic': clinicId,
        'p_patient': patientId,
        'p_version': versionId,
        'p_responsible': responsibleId,
        'p_values': values,
        'p_branding': branding,
        'p_operation': operationId,
      }),
    ),
  );
  @override
  Future<void> signAuthorship(
    String id,
    int revision,
    String name,
    List<List<double>?> signature,
    bool confirmed,
    String operationId,
  ) async {
    await rpc('form_document_authorship_sign', {
      'p_id': id,
      'p_revision': revision,
      'p_name': name,
      'p_signature': signature,
      'p_confirmed': confirmed,
      'p_operation': operationId,
    });
  }

  @override
  Future<Map<String, dynamic>?> templatePermissions(String clinicId) async {
    try {
      return Map<String, dynamic>.from(
        await rpc('form_template_permissions', {'p_clinic': clinicId}) as Map,
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  @override
  Future<FormDocument> useProfile(
    String id,
    int revision,
    String profile,
    bool shareSignature,
  ) async => FormDocument.read(
    Map<String, dynamic>.from(
      await rpc('form_document_use_profile', {
        'p_id': id,
        'p_revision': revision,
        'p_profile': profile,
        'p_share': shareSignature,
      }),
    ),
  );
  @override
  Future<List<Map<String, dynamic>>> staff(String clinicId) async =>
      (await rpc('form_clinical_staff', {'p_clinic': clinicId}) as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
  @override
  Future<Map<String, dynamic>> branding(String clinicId) async =>
      Map<String, dynamic>.from(
        await rpc('form_branding', {'p_clinic': clinicId}),
      );
  @override
  Future<void> saveBranding(
    String clinicId,
    Map<String, dynamic> branding,
  ) async {
    await rpc('form_branding_save', {
      'p_clinic': clinicId,
      'p_branding': branding,
    });
  }

  @override
  Future<List<String>> auxiliaries(String clinicId) async =>
      List<String>.from(await rpc('form_auxiliaries', {'p_clinic': clinicId}));
  @override
  Future<void> assign(String documentId, String? auxiliaryId) async {
    await rpc('form_document_assign', {
      'p_id': documentId,
      'p_aux': auxiliaryId,
    });
  }

  @override
  Future<FormTemplateVersion> version(String versionId) async =>
      FormTemplateVersion.read(
        await client
            .from('form_template_versions')
            .select()
            .eq('id', versionId)
            .single(),
      );
  @override
  Future<List<FormTemplateVersion>> history(String templateId) async =>
      (await client
              .from('form_template_versions')
              .select()
              .eq('template_id', templateId)
              .order('version', ascending: false))
          .map(FormTemplateVersion.read)
          .toList();

  Future<dynamic> rpc(String name, Map<String, dynamic> args) =>
      client.rpc(name, params: args);
  @override
  Future<List<FormTemplateVersion>> templates(String clinicId) async =>
      (await rpc('form_templates_list', {'p_clinic': clinicId}) as List)
          .map((r) => FormTemplateVersion.read(Map<String, dynamic>.from(r)))
          .toList();
  @override
  Future<FormTemplateVersion> saveTemplate(
    String clinicId,
    String? templateId,
    int? expectedVersion,
    String? baseVersionId,
    Map<String, dynamic> schema,
    bool approved,
    String reason,
    String operationId,
  ) async => FormTemplateVersion.read(
    Map<String, dynamic>.from(
      await rpc('form_template_save', {
        'p_clinic': clinicId,
        'p_template': templateId,
        'p_expected': expectedVersion,
        'p_base': baseVersionId,
        'p_schema': validateTemplate(schema),
        'p_approved': approved,
        'p_reason': reason,
        'p_operation': operationId,
      }),
    ),
  );
  Future<ReviewedPdf> edge(Map<String, dynamic> body) async {
    final response = await client.functions.invoke('forms-pdf', body: body);
    final data = Map<String, dynamic>.from(response.data);
    return ReviewedPdf(
      Uint8List.fromList(
        base64Decode((data['pdf'] as String).replaceAll(RegExp(r'\s'), '')),
      ),
      data['hash'] as String,
    );
  }

  @override
  Future<ReviewedPdf> templatePreview(
    String clinicId,
    Map<String, dynamic> schema,
    Map<String, dynamic> branding,
  ) => edge({
    'action': 'template',
    'clinic': clinicId,
    'schema': validateTemplate(schema),
    'branding': branding,
  });
  @override
  Future<List<FormDocument>> documents(String clinicId) async =>
      (await rpc('form_documents_list', {'p_clinic': clinicId}) as List)
          .map((r) => FormDocument.read(Map<String, dynamic>.from(r)))
          .toList();
  @override
  Future<FormDocument> createDocument(
    String clinicId,
    String patientId,
    String versionId,
    Map<String, dynamic> values,
    Map<String, dynamic> branding,
    String operationId,
  ) async => FormDocument.read(
    Map<String, dynamic>.from(
      await rpc('form_document_create', {
        'p_clinic': clinicId,
        'p_patient': patientId,
        'p_version': versionId,
        'p_values': values,
        'p_branding': branding,
        'p_operation': operationId,
      }),
    ),
  );
  @override
  Future<FormDocument> saveDocument(
    String id,
    int revision,
    Map<String, dynamic> values,
    Map<String, dynamic> branding,
  ) async => FormDocument.read(
    Map<String, dynamic>.from(
      await rpc('form_document_save', {
        'p_id': id,
        'p_revision': revision,
        'p_values': values,
        'p_branding': branding,
      }),
    ),
  );
  @override
  Future<FormDocument> prepare(
    String id,
    int revision,
    List<List<double>?> tutorSignature,
    List<List<double>?> mvzSignature,
  ) async => FormDocument.read(
    Map<String, dynamic>.from(
      await rpc('form_document_prepare', {
        'p_id': id,
        'p_revision': revision,
        'p_tutor_signature': tutorSignature,
        'p_mvz_signature': mvzSignature,
      }),
    ),
  );
  @override
  Future<ReviewedPdf> pdf(String id) =>
      edge({'action': 'document', 'document': id});
  @override
  Future<FormDocument> finalize(
    String id,
    int revision,
    String pdfHash,
  ) async => FormDocument.read(
    Map<String, dynamic>.from(
      await rpc('form_document_finalize', {
        'p_id': id,
        'p_revision': revision,
        'p_pdf_hash': pdfHash,
      }),
    ),
  );
}
