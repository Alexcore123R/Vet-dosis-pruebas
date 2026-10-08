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
  bool busy = false, disposed = false;
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
    if (disposed || busy || !access.clinical) return;
    busy = true;
    if (!retainError) error = null;
    changed();
    try {
      final result = await repository.load(member.clinicId);
      if (disposed) return;
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
  }) async {
    if (disposed ||
        busy ||
        !access.clinical ||
        (physician && !access.prescribe)) {
      return false;
    }
    busy = true;
    error = null;
    changed();
    bool success = false;
    try {
      await action();
      success = true;
    } catch (_) {
      if (!disposed) {
        error =
            'No se pudo registrar. El estado puede haber cambiado: actualiza y revisa antes de repetir la acción.';
      }
    }
    if (disposed) return false;
    busy = false;
    await refresh(retainError: true);
    return success;
  }

  Future<bool> perform(HospitalTask task) =>
      mutate(() => repository.perform(member.clinicId, task));
  Future<bool> snooze(HospitalTask task, int minutes, String reason) => mutate(
    () => repository.snooze(
      member.clinicId,
      task,
      minutes,
      hospitalText(reason, max: 500),
    ),
  );
  Future<bool> cancel(HospitalTask task, String reason) => mutate(
    () => repository.cancel(
      member.clinicId,
      task,
      hospitalText(reason, max: 500),
    ),
    physician: true,
  );
  Future<bool> discharge(HospitalStay stay, String reason) => mutate(
    () => repository.discharge(
      member.clinicId,
      stay,
      hospitalText(reason, max: 500),
    ),
    physician: true,
  );
}
