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
  bool busy = false, _disposed = false;
  int _generation = 0;
  String? error;
  Future<void> load({String? caseId}) async {
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final rows = await repository.cases(clinicId, patientId);
      final detail = caseId == null ? null : await repository.bundle(caseId);
      if (_disposed || generation != _generation) return;
      cases = rows;
      selected = detail;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      cases = [];
      selected = null;
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
    super.dispose();
  }
}
