import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/hospital_models.dart';
import '../domain/hospital_repository.dart';
import '../application/hospital_alerts.dart';

class HospitalViewModel extends ChangeNotifier {
  HospitalViewModel(
    this.repository,
    this.member,
    this.alerts, {
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       access = HospitalAccess(member.role) {
    alerts.addListener(changed);
  }
  final HospitalRepository repository;
  final ClinicMembership member;
  final HospitalAlerts alerts;
  final HospitalAccess access;
  final DateTime Function() now;
  String get scope => '${member.userId}:${member.clinicId}:${member.role.name}';
  HospitalSnapshot snapshot = const HospitalSnapshot([], []);
  bool busy = false, disposed = false, explicitPermissions = false;
  bool get canManageAdmission => explicitPermissions
      ? (snapshot.permissions?['hospital.manage'] == true &&
            snapshot.permissions?['patient.read'] == true)
      : access.prescribe;
  bool get canMoveCage =>
      explicitPermissions && snapshot.permissions?['hospital.manage'] == true;
  bool get canSchedule => explicitPermissions
      ? (snapshot.typedReviews &&
            snapshot.permissions?['hospital.schedule'] == true)
      : access.prescribe;
  bool get canDischarge => explicitPermissions
      ? (snapshot.permissions?['hospital.discharge'] == true)
      : access.prescribe;
  bool canTask(HospitalTask task, String action) {
    if (!explicitPermissions) {
      return action == 'cancel' ? access.prescribe : access.clinical;
    }
    if (snapshot.permissions == null) return false;
    for (final current in snapshot.tasks) {
      if (current.id == task.id &&
          current.stayId == task.stayId &&
          current.version == task.version) {
        return current.actions?[action] == true;
      }
    }
    return false;
  }

  String? error, alarmError;
  Timer? _timer;
  void changed() {
    if (!disposed) notifyListeners();
  }

  void start() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  @override
  void dispose() {
    disposed = true;
    _timer?.cancel();
    alerts.removeListener(changed);
    snapshot = const HospitalSnapshot([], []);
    super.dispose();
  }

  Future<void> refresh({bool retainError = false}) async {
    if (disposed || busy || (!explicitPermissions && !access.clinical)) return;
    busy = true;
    if (!retainError) error = null;
    changed();
    try {
      final result = await repository.load(member.clinicId);
      if (disposed) return;
      if (explicitPermissions && result.permissions == null) {
        throw StateError('permission_snapshot_missing');
      }
      if (result.permissions != null) explicitPermissions = true;
      snapshot = result;
      try {
        await alerts.reconcile(scope, result.tasks);
        if (!disposed) alarmError = null;
      } catch (_) {
        if (!disposed) {
          alarmError =
              'No se pudieron actualizar todos los avisos locales. Revisa los permisos y mantén la hoja abierta.';
        }
      }
    } catch (_) {
      if (!disposed) {
        snapshot = const HospitalSnapshot([], []);
        error =
            'No se pudo cargar la hoja. Revisa tu conexión; si persiste, contacta a soporte y verifica el tratamiento actual.';
      }
    } finally {
      if (!disposed) {
        busy = false;
        changed();
      }
    }
  }

  Future<bool> mutate(
    Future<void> Function() action, {
    bool physician = false,
    String? permission,
    bool? explicitAllowed,
  }) async {
    final permitted = explicitPermissions
        ? (explicitAllowed ??
              (permission != null && snapshot.permissions?[permission] == true))
        : access.clinical && (!physician || access.prescribe);
    if (disposed || busy || !permitted) {
      return false;
    }
    busy = true;
    error = null;
    changed();
    bool success = false;
    try {
      await action();
      success = true;
    } catch (e) {
      if (!disposed) {
        error =
            e.toString().contains('discharge_preview_changed') ||
                e.toString().contains('hospital_version_conflict')
            ? 'La estancia o sus indicaciones cambiaron. Actualiza y revisa el alta de nuevo.'
            : 'No se pudo registrar. El estado puede haber cambiado: actualiza y revisa antes de repetir la acción.';
      }
    }
    if (disposed) return false;
    busy = false;
    await refresh(retainError: true);
    return success;
  }

  Future<bool> followup(
    HospitalTask task,
    String action,
    int? minutes,
    String reason,
    String operation,
  ) {
    final source = repository;
    if (!snapshot.medicationFollowup || source is! HospitalResolutionRepository) {
      return Future.value(false);
    }
    return mutate(
      () => (source as HospitalResolutionRepository).followup(
        member.clinicId,
        task,
        action,
        minutes,
        hospitalText(reason, max: 500),
        operation,
      ),
      explicitAllowed: canTask(task, action),
    );
  }

  Future<bool> confirmDischarge(
    HospitalStay stay,
    HospitalDischargePreview preview,
    String reason,
    String operation,
  ) {
    final source = repository;
    if (!snapshot.reviewedDischarge || source is! HospitalResolutionRepository) {
      return Future.value(false);
    }
    return mutate(
      () => (source as HospitalResolutionRepository).confirmDischarge(
        member.clinicId,
        stay,
        preview,
        hospitalText(reason, max: 500),
        operation,
      ),
      explicitAllowed: canDischarge,
    );
  }

  Future<bool> perform(HospitalTask task) => mutate(
    () => repository.perform(member.clinicId, task),
    explicitAllowed: canTask(task, 'perform'),
  );
  Future<bool> snooze(HospitalTask task, int minutes, String reason) => mutate(
    () => repository.snooze(
      member.clinicId,
      task,
      minutes,
      hospitalText(reason, max: 500),
    ),
    explicitAllowed: canTask(task, 'snooze'),
  );
  Future<bool> cancel(HospitalTask task, String reason) => mutate(
    () => repository.cancel(
      member.clinicId,
      task,
      hospitalText(reason, max: 500),
    ),
    physician: true,
    explicitAllowed: canTask(task, 'cancel'),
  );
  Future<bool> discharge(HospitalStay stay, String reason) => mutate(
    () => repository.discharge(
      member.clinicId,
      stay,
      hospitalText(reason, max: 500),
    ),
    physician: true,
    explicitAllowed: canDischarge,
  );
}
