import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/form_models.dart';
import '../domain/form_repository.dart';

class FormViewModel extends ChangeNotifier {
  FormViewModel(this.repository, this.member);
  final FormRepository repository;
  final ClinicMembership member;
  FormsAccess get access => FormsAccess(member.role);
  bool templateKnown = false;
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
  bool get documentsAvailable => !templateKnown;
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
      final documentRows = contract != null
          ? <FormDocument>[]
          : await repository.documents(member.clinicId);
      if (closed) return;
      templatePermissions = contract;
      templates = templateRows;
      documents = documentRows;
    } catch (_) {
      if (closed) return;
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
