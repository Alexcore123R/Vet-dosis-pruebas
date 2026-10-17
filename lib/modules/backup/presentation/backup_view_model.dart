import 'package:flutter/foundation.dart';
import '../domain/backup_repository.dart';

class BackupViewModel extends ChangeNotifier {
  BackupViewModel(this.repository, this.clinic);
  final BackupRepository repository;
  final String clinic;
  Map<String, dynamic> data = {};
  bool busy = false, _disposed = false;
  String? error;
  Future<void> load() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      data = await repository.statistics(clinic);
    } catch (_) {
      data = {};
      error =
          'No se pudieron consultar las estadísticas. Revisa conexión y permisos.';
    }
    if (_disposed) return;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
