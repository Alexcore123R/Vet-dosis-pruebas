import 'package:flutter/foundation.dart';
import '../domain/inventory_repository.dart';

class PaymentsViewModel extends ChangeNotifier {
  PaymentsViewModel(this.repository, this.clinic);
  final InventoryRepository repository;
  final String clinic;
  Map<String, dynamic> data = {};
  bool busy = false, _disposed = false;
  String? error;
  bool managementKnown = false;
  Map<String, dynamic>? management;
  bool get canReport =>
      !busy &&
      error == null &&
      (!managementKnown || management?['actions']?['sales.collect'] == true);
  bool canReconcile(bool legacy) =>
      !busy &&
      error == null &&
      (managementKnown
          ? (management?['actions']?['sales.reconcile'] == true &&
                management?['actions']?['sales.read'] == true)
          : legacy);

  List<Map<String, dynamic>> rows(String name) => (data[name] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Future<void> load() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final repo = repository;
      final contract = repo is InventoryManagementRepository
          ? await (repo as InventoryManagementRepository).managementPermissions(
              clinic,
            )
          : null;
      if (_disposed) return;
      if (contract != null) {
        managementKnown = true;
        if (contract['schema_version'] != 1 ||
            contract['mode'] != 'explicit_inventory' ||
            contract['actions'] is! Map) {
          throw StateError('unknown_inventory_contract');
        }
      } else if (managementKnown) {
        throw StateError('inventory_contract_lost');
      }
      final r = await repository.read('pay_dashboard', {'p_clinic': clinic});
      if (_disposed) return;
      management = contract;
      data = Map<String, dynamic>.from(r as Map);
    } catch (_) {
      if (_disposed) return;
      management = null;
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
    management = null;
    data = {};
    super.dispose();
  }
}
