import 'package:flutter/foundation.dart';
import '../domain/support_repository.dart';

class SupportViewModel extends ChangeNotifier {
  SupportViewModel(this.repository, this.clinic);
  final SupportRepository repository;
  final String clinic;
  List<Map<String, dynamic>> tickets = [];
  Map<String, dynamic>? detail;
  bool busy = false, _disposed = false;
  String? error;
  int _generation = 0;
  Future<void> load({String? ticket}) async {
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final rows = await repository.tickets(clinic);
      final data = ticket == null ? null : await repository.detail(ticket);
      if (_disposed || generation != _generation) return;
      tickets = rows;
      detail = data;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      tickets = [];
      detail = null;
      error = 'No se pudo consultar soporte. Revisa tu conexión y acceso.';
    }
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
