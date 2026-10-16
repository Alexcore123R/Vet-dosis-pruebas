import 'package:flutter/foundation.dart';
import 'clinical_models.dart';
import 'clinical_repository.dart';

class ClinicalViewModel extends ChangeNotifier {
  ClinicalViewModel(this.repository, this.clinicId, this.patientId);
  final ClinicalRepository repository;
  final String clinicId;
  final String? patientId;
  List<ClinicalCase> cases = [];
  ClinicalBundle? selected;
  bool permissionsKnown = false;
  Map<String, dynamic>? workspace;
  bool can(String key) =>
      !busy && error == null && workspace?['actions']?[key] == true;
  List<Map<String, dynamic>> rows(String key) =>
      (workspace?[key] as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
  List<String> get actScopes =>
      List<String>.from(workspace?['act_scopes'] as List? ?? []);
  void validateWorkspace(Map<String, dynamic> value, String? caseId) {
    if (value['schema_version'] != 1 ||
        value['mode'] != 'explicit_clinical' ||
        value['clinic_id'] != clinicId ||
        value['case_id'] != caseId ||
        value['can_read'] is! bool ||
        value['actions'] is! Map ||
        const [
          'observe',
          'act',
          'correct',
          'authorize',
          'revoke',
          'bind',
        ].any((k) => value['actions'][k] is! bool) ||
        value['act_scopes'] is! List ||
        (value['act_scopes'] as List).any(
          (s) => !clinicalScopes.containsKey(s) || s == 'observaciones',
        ) ||
        const [
          'bindings',
          'documents',
          'members',
          'procedures',
        ].any((k) => value[k] is! List)) {
      throw StateError('unknown_clinical_workspace');
    }
    for (final key in ['documents', 'members', 'procedures']) {
      if ((value[key] as List).any(
        (r) =>
            r is! Map ||
            r['id'] is! String ||
            r[key == 'documents'
                    ? 'title'
                    : key == 'members'
                    ? 'label'
                    : 'name']
                is! String,
      )) {
        throw StateError('unknown_clinical_workspace');
      }
    }
    if ((value['documents'] as List).any(
      (r) =>
          r['state'] != 'signed' ||
          r['revision'] is! int ||
          r['revision'] < 1 ||
          r['is_original'] is! bool,
    )) {
      throw StateError('unknown_clinical_workspace');
    }
    if ((value['bindings'] as List).any(
      (r) =>
          r is! Map ||
          !clinicalScopes.containsKey(r['scope']) ||
          r['procedure_id'] is! String ||
          r['professional_required'] is! bool ||
          r['source'] is! String,
    )) {
      throw StateError('unknown_clinical_workspace');
    }
    if (value['actions']['act'] == true &&
        (value['act_scopes'] as List).isEmpty) {
      throw StateError('unknown_clinical_workspace');
    }
  }

  bool busy = false, _disposed = false;
  int _generation = 0;
  String? error;
  Future<void> load({String? caseId}) async {
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final source = repository;
      final contract = source is ClinicalPermissionRepository
          ? await (source as ClinicalPermissionRepository).workspace(
              clinicId,
              caseId,
            )
          : null;
      if (_disposed || generation != _generation) return;
      if (contract != null) {
        permissionsKnown = true;
        validateWorkspace(contract, caseId);
      } else if (permissionsKnown) {
        throw StateError('clinical_workspace_lost');
      }
      final rows = contract == null || contract['can_read'] == true
          ? await repository.cases(clinicId, patientId)
          : <ClinicalCase>[];
      if (caseId != null && contract != null && contract['can_read'] != true) {
        throw StateError('clinical_access_denied');
      }
      final detail = caseId == null ? null : await repository.bundle(caseId);
      if (_disposed || generation != _generation) return;
      cases = rows;
      selected = detail;
      workspace = contract;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      cases = [];
      selected = null;
      workspace = null;
      error = 'No se pudo consultar el caso. Revisa acceso y conexión.';
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    cases = [];
    selected = null;
    workspace = null;
    super.dispose();
  }
}
