import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../core/domain/navigation_access.dart';
import '../../operations/domain/operations_repository.dart';
import '../../inventory/domain/inventory_repository.dart';
import '../../hospital/domain/hospital_repository.dart';
import '../../hospital/domain/hospital_models.dart';
import '../../patients/domain/patient_repository.dart';
import '../../backup/domain/backup_repository.dart';

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required this.member,
    this.operations,
    this.inventory,
    this.hospital,
    this.patients,
    this.backup,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final ClinicMembership? member;
  final OperationsRepository? operations;
  final InventoryRepository? inventory;
  final HospitalRepository? hospital;
  final PatientRepository? patients;
  final BackupRepository? backup;
  final DateTime Function() now;
  final Map<String, String> errors = {};
  Map<String, dynamic>? agenda, stock, statistics;
  HospitalSnapshot? ward;
  int? patientCount;
  bool busy = false, _disposed = false;
  DateTime? updated;
  Future<void> load({bool offline = false}) async {
    if (busy) return;
    agenda = stock = statistics = null;
    ward = null;
    patientCount = null;
    updated = null;
    errors.clear();
    if (member == null || offline) {
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    Future<void> section(String name, Future<void> Function() read) async {
      try {
        await read();
      } catch (_) {
        errors[name] = 'No se pudo cargar. Revisa conexión y permisos.';
      }
    }

    final m = member!;
    await Future.wait([
      if (operations != null)
        section('Agenda', () async {
          agenda = await operations!.dashboard(m.clinicId);
        }),
      if (inventory != null && navigationAllowed('Inventario', m))
        section('Inventario', () async {
          stock = Map<String, dynamic>.from(
            await inventory!.read('inv_dashboard', {'p_clinic': m.clinicId})
                as Map,
          );
        }),
      if (hospital != null && navigationAllowed('Hospitalización', m))
        section('Hospitalización', () async {
          ward = await hospital!.load(m.clinicId);
        }),
      if (patients != null && m.role != ClinicRole.estilista)
        section('Pacientes', () async {
          patientCount = (await patients!.patients(m.clinicId)).length;
        }),
      if (backup != null && navigationAllowed('Estadísticas', m))
        section('Estadísticas', () async {
          statistics = await backup!.statistics(m.clinicId);
        }),
    ]);
    if (_disposed) return;
    busy = false;
    updated = now();
    notifyListeners();
  }

  List<Map<String, dynamic>> rows(Map<String, dynamic>? data, String key) =>
      (data?[key] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  List<Map<String, dynamic>> get products =>
      rows(stock, 'products').where((p) => p['active'] != false).toList();
  List<Map<String, dynamic>> get lowStock =>
      products.where((p) => p['low_stock'] == true).toList();
  DateTime? starts(Map<String, dynamic> a) =>
      DateTime.tryParse('${a['starts_at'] ?? ''}');
  List<Map<String, dynamic>> get upcoming {
    final result = rows(agenda, 'appointments')
        .where(
          (a) =>
              a['state'] == 'agendado' && (starts(a)?.isAfter(now()) ?? false),
        )
        .toList();
    result.sort((a, b) => starts(a)!.compareTo(starts(b)!));
    return result;
  }

  List<Map<String, dynamic>> get recent {
    final result = rows(
      agenda,
      'appointments',
    ).where((a) => starts(a) != null && !starts(a)!.isAfter(now())).toList();
    result.sort((a, b) => starts(b)!.compareTo(starts(a)!));
    return result;
  }

  DateTime effectiveTime(HospitalTask task) =>
      task.snoozedUntil != null && task.snoozedUntil!.isAfter(task.dueAt)
      ? task.snoozedUntil!
      : task.dueAt;
  List<HospitalTask> get medication {
    final result = (ward?.tasks ?? [])
        .where(
          (t) => t.state == HospitalTaskState.pending && t.kind == 'medicacion',
        )
        .toList();
    result.sort((a, b) => effectiveTime(a).compareTo(effectiveTime(b)));
    return result;
  }

  List<HospitalTask> get overdue =>
      medication.where((t) => !effectiveTime(t).isAfter(now())).toList();
  List<HospitalTask> get nextDoses =>
      medication.where((t) => effectiveTime(t).isAfter(now())).toList();
  String patient(HospitalTask task) {
    for (final stay in ward?.stays ?? <HospitalStay>[]) {
      if (stay.id == task.stayId) return stay.patientName;
    }
    return 'Paciente no disponible';
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
