import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../../doses/domain/quantity.dart';
import '../../inventory/domain/inventory_models.dart';
import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../core/domain/navigation_access.dart';
import '../../operations/domain/operations_repository.dart';
import '../../inventory/domain/inventory_repository.dart';
import '../../hospital/domain/hospital_repository.dart';
import '../../hospital/domain/hospital_models.dart';
import '../../patients/domain/patient_repository.dart';
import '../../backup/domain/backup_repository.dart';
import '../../core/domain/module_access.dart';
import '../../attendance/domain/attendance_repository.dart';

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required this.member,
    this.operations,
    this.inventory,
    this.hospital,
    this.patients,
    this.backup,
    this.moduleAccess,
    this.attendance,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final ClinicMembership? member;
  final OperationsRepository? operations;
  final InventoryRepository? inventory;
  final HospitalRepository? hospital;
  final PatientRepository? patients;
  final BackupRepository? backup;
  final ModuleAccess? moduleAccess;
  final AttendanceRepository? attendance;
  final DateTime Function() now;
  bool get canSeeClinicSales => moduleAccess == null
      ? member?.role == ClinicRole.admin
      : moduleAccess!.summary('sales');
  bool get canSeePatients => moduleAccess == null
      ? member?.role != ClinicRole.estilista
      : moduleAccess!.summary('patients');
  bool canSummarize(String name) =>
      moduleAccess == null || moduleAccess!.summary(name);
  final Map<String, String> errors = {};
  Map<String, dynamic>? agenda, stock, statistics, commissions, attendanceWeek;
  HospitalSnapshot? ward;
  int? patientCount;
  bool busy = false, _disposed = false;
  DateTime? updated;
  Future<void> load({bool offline = false}) async {
    if (busy) return;
    agenda = stock = statistics = commissions = attendanceWeek = null;
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
      if (operations != null &&
          (canSummarize('agenda') || moduleAccess?.module('agenda') == true))
        section('Agenda', () async {
          agenda = await operations!.dashboard(m.clinicId);
        }),
      if (operations is CommissionRepository &&
          (moduleAccess == null || moduleAccess!.module('agenda')))
        section('Comisiones', () async {
          commissions = await (operations as CommissionRepository).commissionAccount(m.clinicId);
        }),
      if (attendance != null && !m.isPersonal &&
          (moduleAccess == null || moduleAccess!.module('agenda')))
        section('Checado', () async {
          attendanceWeek = await attendance!.dashboard(m.clinicId);
        }),
      if (inventory != null && canSummarize('inventory'))
        section('Inventario', () async {
          stock = Map<String, dynamic>.from(
            await inventory!.read('inv_dashboard', {'p_clinic': m.clinicId})
                as Map,
          );
        }),
      if (hospital != null && canSummarize('hospital'))
        section('Hospitalización', () async {
          ward = await hospital!.load(m.clinicId);
        }),
      if (patients != null && canSeePatients)
        section('Pacientes', () async {
          patientCount = (await patients!.patients(m.clinicId)).length;
        }),
      if (backup != null && navigationAllowed('Estadísticas', m, moduleAccess))
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

  static bool _zonesReady = false;
  String? get clinicTimezone =>
      (stock?['timezone'] ?? statistics?['timezone']) as String?;
  DateTime localTime(DateTime value) {
    final zone = clinicTimezone;
    if (zone == null) return value.toLocal();
    if (!_zonesReady) {
      tzdata.initializeTimeZones();
      _zonesReady = true;
    }
    try {
      return tz.TZDateTime.from(value, tz.getLocation(zone));
    } catch (_) {
      return value.toLocal();
    }
  }

  List<Map<String, dynamic>> get todayAppointments {
    final today = localTime(now());
    return upcoming
        .where((a) {
          final date = localTime(starts(a)!);
          return date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
        })
        .take(4)
        .toList();
  }

  Map<String, Quantity>? get stockByUnit {
    if (stock == null) return null;
    try {
      final result = <String, Quantity>{};
      for (final p in products) {
        final unit = p['stock_unit'] as String?;
        if (unit == null || unit.isEmpty) return null;
        final qty = Quantity.parse('${p['available_stock']}');
        final before = result[unit] ?? Quantity.parse('0');
        result[unit] = Quantity(
          before.n * qty.d + qty.n * before.d,
          before.d * qty.d,
        );
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  Money? get valueAtSale {
    if (stock == null) return null;
    try {
      var sum = Money(BigInt.zero);
      for (final p in products) {
        sum =
            sum +
            Money.parse(
              '${p['precio_venta']}',
            ).times(Quantity.parse('${p['available_stock']}'));
      }
      return sum;
    } catch (_) {
      return null;
    }
  }

  Money? get valueAtCost {
    if (stock == null) return null;
    try {
      var sum = Money(BigInt.zero);
      for (final p in products) {
        if (p['lots'] is! List) return null;
        for (final lot in (p['lots'] as List).cast<Map>()) {
          if (lot['expired'] == true ||
              (lot['caducidad'] == null && p['m8_kind'] != 'producto')) {
            continue;
          }
          sum =
              sum +
              Money.parse(
                '${lot['costo_unitario']}',
              ).times(Quantity.parse('${lot['cantidad']}'));
        }
      }
      return sum;
    } catch (_) {
      return null;
    }
  }

  Money? get potentialMargin => valueAtSale != null && valueAtCost != null
      ? valueAtSale! - valueAtCost!
      : null;
  Map<String, dynamic>? get dayTotals => stock?['day_totals'] is Map
      ? Map<String, dynamic>.from(stock!['day_totals'] as Map)
      : null;
  Map<String, dynamic>? get ownShift => rows(stock, 'shifts')
      .where((s) => s['cashier_id'] == member?.userId && s['closed_at'] == null)
      .firstOrNull;
  List<Map<String, dynamic>> get recentCuts => rows(
    stock,
    'shifts',
  ).where((s) => s['closed_at'] != null).take(3).toList();
  List<Map<String, dynamic>> get pendingTasks =>
      rows(agenda, 'tasks').where((t) => t['completed_at'] == null).toList();
  List<Map<String, dynamic>> get todayTasks {
    final day = localTime(now());
    final date = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return pendingTasks.where((t) => t['scheduled_on'] == date).toList();
  }
  List<Map<String, dynamic>> get notices => rows(agenda, 'messages')
      .where((m) => m['category'] == 'aviso').toList().reversed.take(4).toList();
  List<Map<String, dynamic>> get messages =>
      rows(agenda, 'messages').reversed.take(4).toList();
  Map<String, dynamic>? get ownCommission => rows(commissions, 'accrued')
      .where((r) => r['professional_id'] == member?.userId).firstOrNull;

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
