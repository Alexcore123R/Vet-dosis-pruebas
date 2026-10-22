import 'package:flutter/foundation.dart';
import '../domain/preventive_repository.dart';

class PreventiveModel extends ChangeNotifier {
  PreventiveModel(this.repository, this.clinic, this.patient);
  final PreventiveRepository repository;
  final String clinic, patient;
  Map<String, dynamic>? data;
  String? error;
  bool busy = false, disposed = false;
  int generation = 0;
  List<Map<String, dynamic>> rows(String key) => (data?[key] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  void clear() {
    generation++;
    data = null;
    busy = false;
    if (!disposed) notifyListeners();
  }

  Future<void> load() async {
    if (disposed) return;
    final request = ++generation;
    busy = true;
    data = null;
    error = null;
    notifyListeners();
    try {
      final next = await repository.booklet(clinic, patient);
      if (next['schema_version'] != 2 ||
          next['clinic_id'] != clinic ||
          next['patient_id'] != patient ||
          [
            'events',
            'evidence',
            'plans',
            'retired',
            'links',
            'members',
          ].any((k) => next[k] is! List) ||
          [
            'can_attach',
            'can_confirm',
            'can_schedule',
          ].any((k) => next[k] is! bool)) {
        throw const FormatException('Contrato de carnet no compatible.');
      }
      if (!disposed && request == generation) data = next;
    } catch (_) {
      if (!disposed && request == generation) {
        error =
            'No se pudo comprobar el carnet. Revisa la conexión y los permisos; los datos anteriores se retiraron.';
      }
    } finally {
      if (!disposed && request == generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    data = null;
    super.dispose();
  }
}
