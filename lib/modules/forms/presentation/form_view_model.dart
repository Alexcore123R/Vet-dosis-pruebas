import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/form_models.dart';
import '../domain/form_repository.dart';

class FormViewModel extends ChangeNotifier {
  FormViewModel(this.repository, this.member);
  final FormRepository repository;
  final ClinicMembership member;
  FormsAccess get access => FormsAccess(member.role);
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
      if (!access.clinical) throw StateError('Acceso clínico requerido.');
      final data = await Future.wait([
        repository.templates(member.clinicId),
        repository.documents(member.clinicId),
      ]);
      if (closed) return;
      templates = data[0] as List<FormTemplateVersion>;
      documents = data[1] as List<FormDocument>;
    } catch (_) {
      if (closed) return;
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
