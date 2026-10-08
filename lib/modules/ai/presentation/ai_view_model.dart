import 'package:flutter/foundation.dart';
import '../domain/ai_repository.dart';

class AiViewModel extends ChangeNotifier {
  AiViewModel(this.repository, this.clinic);
  final AiRepository repository;
  final String clinic;
  Map<String, dynamic> data = {};
  List<Map<String, dynamic>> messages = [];
  String? selected, error;
  bool busy = false, _disposed = false;
  int _generation = 0;
  List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Future<void> load({String? chat}) async {
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final r = await repository.dashboard(clinic);
      final chats = (r['chats'] as List? ?? []);
      final id = chat ?? selected;
      final allowed = chats.any((c) => c['id'] == id);
      final m = allowed
          ? await repository.messages(id!)
          : <Map<String, dynamic>>[];
      if (_disposed || generation != _generation) return;
      data = r;
      selected = allowed ? id : null;
      messages = m;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      data = {};
      selected = null;
      messages = [];
      error =
          'No se pudo consultar IA. Revisa conexión y acceso; los datos anteriores se ocultaron.';
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
