import 'package:flutter/foundation.dart';
import '../domain/patient_activity.dart';

class PatientActivityModel extends ChangeNotifier {
  PatientActivityModel(this.repository, this.clinic);
  final PatientActivityRepository repository;
  final String clinic;
  PatientActivitySnapshot? snapshot;
  bool busy = false;
  String? error;
  bool _disposed = false;
  int _generation = 0;

  void clear() {
    if (_disposed) return;
    _generation++;
    snapshot = null;
    error = null;
    busy = false;
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed || busy) return;
    final generation = ++_generation;
    busy = true;
    snapshot = null;
    error = null;
    notifyListeners();
    try {
      final result = await repository.activity(clinic);
      if (_disposed || generation != _generation) return;
      snapshot = result;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      snapshot = null;
      error =
          'No se pudo comprobar la actividad. Actualiza; no se muestran estados anteriores.';
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
    snapshot = null;
    super.dispose();
  }
}
