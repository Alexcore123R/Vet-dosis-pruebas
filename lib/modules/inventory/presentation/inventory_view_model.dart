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
  bool managementKnown = false;
  Map<String, dynamic>? management;
  bool allowed(String code, {bool legacy = false}) =>
      !busy &&
      error == null &&
      (managementKnown ? (management?['actions']?[code] == true) : legacy);
  bool get canManage => allowed('inventory.manage', legacy: admin);
  bool get canReceive => allowed('inventory.receive', legacy: admin);
  bool get canAdjust => allowed('inventory.adjust', legacy: admin);
  bool get canCollect => allowed('sales.collect', legacy: true);
  bool get canReadFinance => allowed('sales.read', legacy: admin);
  bool get canMoveCash => canCollect && allowed('cash.move', legacy: true);
  bool get canReverse => canCollect && allowed('sales.reverse', legacy: admin);
  bool get canManual => allowed('sales.manual', legacy: admin);
  bool get canPrepareOrder => allowed('inventory.order.prepare', legacy: admin);
  bool get canApproveOrder => allowed('inventory.order.approve', legacy: admin);
  bool get canLinkVial =>
      !busy &&
      error == null &&
      (managementKnown
          ? (management?['can_link_vial'] == true)
          : (dashboard?['professional'] == true));
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
      final managementContract = repo is InventoryManagementRepository
          ? await (repo as InventoryManagementRepository).managementPermissions(
              member.clinicId,
            )
          : null;
      if (disposed || revision != generation) return;
      if (managementContract != null) {
        managementKnown = true;
        if (managementContract['schema_version'] != 1 ||
            managementContract['mode'] != 'explicit_inventory' ||
            managementContract['actions'] is! Map) {
          throw StateError('unknown_inventory_contract');
        }
      } else if (managementKnown) {
        throw StateError('inventory_contract_lost');
      }
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
      management = managementContract;
      dispensing = permissions;
      dashboard = Map<String, dynamic>.from(data);
      cut = null;
    } catch (_) {
      if (disposed || revision != generation) return;
      management = null;
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
    try {
      final result = Map<String, dynamic>.from(
        await repository.read('inv_shift_snapshot', {'p_shift': id}),
      );
      if (!disposed && revision == generation && cutRevision == cutGeneration) {
        cut = result;
        notifyListeners();
      }
      return result;
    } catch (_) {
      if (!disposed && revision == generation && cutRevision == cutGeneration) {
        cut = null;
        error = 'No se pudo consultar el corte. Actualiza y revisa tu acceso.';
        notifyListeners();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    management = null;
    dispensing = null;
    dashboard = null;
    cut = null;
    super.dispose();
  }
}
