import 'package:flutter/foundation.dart';
import '../domain/inventory_repository.dart';

class PaymentsViewModel extends ChangeNotifier {
  PaymentsViewModel(this.repository, this.clinic);
  final InventoryRepository repository;
  final String clinic;
  Map<String, dynamic> data = {};
  bool busy = false, _disposed = false;
  String? error;
  List<Map<String, dynamic>> rows(String name) => (data[name] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Future<void> load() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final r = await repository.read('pay_dashboard', {'p_clinic': clinic});
      if (_disposed) return;
      data = Map<String, dynamic>.from(r as Map);
    } catch (_) {
      if (_disposed) return;
      data = {};
      error =
          'No se pudieron consultar las transacciones. Revisa conexión y permisos.';
    }
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
