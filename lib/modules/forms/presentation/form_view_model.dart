import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/form_models.dart';
import '../domain/form_repository.dart';

class FormViewModel extends ChangeNotifier {
  FormViewModel(this.repository, this.member);
  final FormRepository repository;
  final ClinicMembership member;
  FormsAccess get access => FormsAccess(member.role);
  bool templateKnown = false, documentsKnown = false;
  Map<String, dynamic>? documentWorkspace;
  List<Map<String, dynamic>> get documentResponsibles =>
      (documentWorkspace?['responsibles'] as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
  bool canCreateDraft(FormTemplateVersion v) =>
      !busy &&
      error == null &&
      documentWorkspace?['can_prepare'] == true &&
      (documentWorkspace?['approved_template_ids'] as List? ?? []).contains(
        v.id,
      );

  Map<String, dynamic>? templatePermissions;
  bool capability(String key) =>
      !busy && error == null && templatePermissions?[key] == true;
  bool get canEditTemplates => templateKnown
      ? capability('can_edit')
      : access.editTemplates && error == null;
  bool get canApproveTemplates => templateKnown
      ? capability('can_approve')
      : access.editTemplates && error == null;
  bool get canBrand => templateKnown
      ? capability('can_brand')
      : member.role == ClinicRole.admin && error == null;
  // Template governance does not confer authority over patient documents.
  bool get documentsAvailable =>
      documentsKnown ? documentWorkspace != null : !templateKnown;
  List<FormTemplateVersion> templates = [];
  List<FormDocument> documents = [];
  bool busy = false, closed = false;
  String? error;
  Future<void> load() async {
    if (closed || busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final source = repository;
      final contract = source is FormTemplatePermissionRepository
          ? await (source as FormTemplatePermissionRepository)
                .templatePermissions(member.clinicId)
          : null;
      if (contract != null) {
        templateKnown = true;
        if (contract['schema_version'] != 1 ||
            contract['mode'] != 'templates_only' ||
            [
              'can_read',
              'can_edit',
              'can_approve',
              'can_brand',
            ].any((k) => contract[k] is! bool)) {
          throw StateError('unknown_template_permission_contract');
        }
        if ((contract['can_read'] != true &&
                [
                  'can_edit',
                  'can_approve',
                  'can_brand',
                ].any((k) => contract[k] == true)) ||
            (contract['can_approve'] == true && contract['can_edit'] != true)) {
          throw StateError('inconsistent_template_permission_contract');
        }
      } else if (templateKnown) {
        throw StateError('template_permission_contract_lost');
      }
      if (contract == null && !access.clinical) {
        throw StateError('Acceso clínico requerido.');
      }
      final templateRows = contract != null && contract['can_read'] != true
          ? <FormTemplateVersion>[]
          : await repository.templates(member.clinicId);
      final draftSource = repository;
      final workspace = draftSource is FormDraftRepository
          ? await (draftSource as FormDraftRepository).documentWorkspace(
              member.clinicId,
            )
          : null;
      if (workspace != null) {
        documentsKnown = true;
        if (workspace['schema_version'] != 1 ||
            workspace['mode'] != 'draft_authorship' ||
            workspace['can_read'] is! bool ||
            workspace['can_prepare'] is! bool ||
            workspace['responsibles'] is! List ||
            (workspace['responsibles'] as List).any(
              (r) =>
                  r is! Map ||
                  r['id'] is! String ||
                  r['name'] is! String ||
                  r['license'] is! String,
            ) ||
            workspace['approved_template_ids'] is! List ||
            (workspace['approved_template_ids'] as List).any(
              (r) => r is! String,
            ) ||
            (workspace['can_prepare'] == true &&
                workspace['can_read'] != true)) {
          throw StateError('unknown_document_workspace');
        }
      } else if (documentsKnown) {
        throw StateError('document_workspace_lost');
      }
      final documentRows = workspace != null
          ? workspace['can_read'] == true
                ? await repository.documents(member.clinicId)
                : <FormDocument>[]
          : contract != null
          ? <FormDocument>[]
          : await repository.documents(member.clinicId);
      if (closed) return;
      documentWorkspace = workspace;
      templatePermissions = contract;
      templates = templateRows;
      documents = documentRows;
    } catch (_) {
      if (closed) return;
      documentWorkspace = null;
      templatePermissions = null;
      templates = [];
      documents = [];
      error =
          'No se pudieron consultar los formatos. Revisa conexión y permisos; si persiste, contacta a soporte.';
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    closed = true;
    documentWorkspace = null;
    templatePermissions = null;
    templates = [];
    documents = [];
    super.dispose();
  }
}

class PdfReviewSession {
  FormDocument? document;
  ReviewedPdf? reviewed;
  bool accepted = false;
  void setDocument(FormDocument value) {
    document = value;
    reviewed = null;
    accepted = false;
  }

  void setPdf(ReviewedPdf value) {
    if (document == null || document!.signed) {
      throw StateError('Documento no revisable.');
    }
    reviewed = value;
    accepted = false;
  }

  void invalidate() {
    reviewed = null;
    accepted = false;
  }

  bool get canFinalize =>
      document != null && reviewed != null && accepted && !document!.signed;
}
