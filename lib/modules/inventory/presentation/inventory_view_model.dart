import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/inventory_repository.dart';

class InventoryViewModel extends ChangeNotifier {
  InventoryViewModel(this.repository, this.member);
  final InventoryRepository repository;
  final ClinicMembership member;
  Map<String, dynamic>? dashboard;
  Map<String, dynamic>? cut;
  String? error;
  bool busy = false, disposed = false;
  int generation = 0;
  int cutGeneration = 0;
  bool dispensingKnown = false;
  Map<String, dynamic>? dispensing;
  bool get canDispense =>
      !busy &&
      error == null &&
      (dispensingKnown
          ? (dispensing?['can_dispense'] == true)
          : (dashboard?['professional'] == true));
  bool get canAuthorizeDispensing =>
      !busy &&
      error == null &&
      (dispensingKnown
          ? (dispensing?['can_authorize'] == true)
          : (dashboard?['professional'] == true));
  bool get admin => member.role == ClinicRole.admin;
  List<Map<String, dynamic>> rows(String key) =>
      (dashboard?[key] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  List<Map<String, dynamic>> get products => rows('products');
  Map<String, dynamic>? get ownShift {
    final matches = rows('shifts')
        .where(
          (s) => s['cashier_id'] == member.userId && s['closed_at'] == null,
        )
        .toList();
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> load() async {
    final revision = ++generation;
    cutGeneration++;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final repo = repository;
      final permissions = repo is DispensingPermissionRepository
          ? await (repo as DispensingPermissionRepository)
                .dispensingPermissions(member.clinicId)
          : null;
      if (disposed || revision != generation) return;
      if (permissions != null) {
        dispensingKnown = true;
        if (permissions['schema_version'] != 1 ||
            permissions['mode'] != 'verified_dispensing') {
          throw StateError('unknown_dispensing_contract');
        }
      } else if (dispensingKnown) {
        throw StateError('dispensing_contract_lost');
      }
      final data = await repository.read('inv_dashboard', {
        'p_clinic': member.clinicId,
      });
      if (disposed || revision != generation) return;
      dispensing = permissions;
      dashboard = Map<String, dynamic>.from(data);
      cut = null;
    } catch (_) {
      if (disposed || revision != generation) return;
      dispensing = null;
      dashboard = null;
      cut = null;
      error =
          'No se pudo cargar inventario. Revisa tu conexión y acceso; si persiste, contacta a soporte.';
    }
    if (!disposed && revision == generation) {
      busy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> readCut(String id) async {
    final revision = generation;
    final cutRevision = ++cutGeneration;
    final result = Map<String, dynamic>.from(
      await repository.read('inv_shift_snapshot', {'p_shift': id}),
    );
    if (!disposed && revision == generation && cutRevision == cutGeneration) {
      cut = result;
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    dispensing = null;
    dashboard = null;
    cut = null;
    super.dispose();
  }
}
