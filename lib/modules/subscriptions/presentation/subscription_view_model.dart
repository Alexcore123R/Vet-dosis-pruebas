import 'package:flutter/foundation.dart';
import '../domain/subscription_repository.dart';

class SubscriptionViewModel extends ChangeNotifier {
  SubscriptionViewModel(this.repository, this.clinic);
  final SubscriptionRepository repository;
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
      final r = await repository.dashboard(clinic);
      if (_disposed) return;
      data = r;
    } catch (_) {
      if (_disposed) return;
      data = {};
      error = 'No se pudo consultar tu plan. Revisa conexión y permisos.';
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
