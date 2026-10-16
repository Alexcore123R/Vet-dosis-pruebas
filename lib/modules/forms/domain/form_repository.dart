import 'form_models.dart';

abstract interface class FormRepository {
  Future<FormDocument> useProfile(
    String id,
    int revision,
    String profile,
    bool shareSignature,
  );
  Future<List<Map<String, dynamic>>> staff(String clinicId);
  Future<Map<String, dynamic>> branding(String clinicId);
  Future<void> saveBranding(String clinicId, Map<String, dynamic> branding);
  Future<List<String>> auxiliaries(String clinicId);
  Future<void> assign(String documentId, String? auxiliaryId);
  Future<FormTemplateVersion> version(String versionId);
  Future<List<FormTemplateVersion>> history(String templateId);
  Future<List<FormTemplateVersion>> templates(String clinicId);
  Future<FormTemplateVersion> saveTemplate(
    String clinicId,
    String? templateId,
    int? expectedVersion,
    String? baseVersionId,
    Map<String, dynamic> schema,
    bool approved,
    String reason,
    String operationId,
  );
  Future<ReviewedPdf> templatePreview(
    String clinicId,
    Map<String, dynamic> schema,
    Map<String, dynamic> branding,
  );
  Future<List<FormDocument>> documents(String clinicId);
  Future<FormDocument> createDocument(
    String clinicId,
    String patientId,
    String versionId,
    Map<String, dynamic> values,
    Map<String, dynamic> branding,
    String operationId,
  );
  Future<FormDocument> saveDocument(
    String id,
    int revision,
    Map<String, dynamic> values,
    Map<String, dynamic> branding,
  );
  Future<FormDocument> prepare(
    String id,
    int revision,
    List<List<double>?> tutorSignature,
    List<List<double>?> mvzSignature,
  );
  Future<ReviewedPdf> pdf(String id);
  Future<FormDocument> finalize(String id, int revision, String pdfHash);
}

abstract interface class FormTemplatePermissionRepository {
  Future<Map<String, dynamic>?> templatePermissions(String clinicId);
}

abstract interface class FormDraftRepository {
  Future<Map<String, dynamic>?> documentWorkspace(String clinicId);
  Future<FormDocument> createAttributedDraft(
    String clinicId,
    String patientId,
    String versionId,
    String responsibleId,
    Map<String, dynamic> values,
    Map<String, dynamic> branding,
    String operationId,
  );
  Future<void> signAuthorship(
    String id,
    int revision,
    String name,
    List<List<double>?> signature,
    bool confirmed,
    String operationId,
  );
}

abstract interface class FormWorkflowRepository {
  Future<Map<String, dynamic>> documentFlow(String id);
  Future<void> flowAction(String action, Map<String, dynamic> arguments);
  Future<ReviewedPdf> tutorPreview(String id);
}
