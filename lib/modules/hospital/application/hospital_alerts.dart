import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/hospital_models.dart';

abstract interface class AlarmBackend {
  bool get supported;
  String get timingNotice;
  Future<void> initialize();
  Future<String> requestPermission();
  Future<void> schedule(int id, AlarmJob job);
  Future<void> cancel(int id);
}

class HospitalAlerts extends ChangeNotifier {
  HospitalAlerts(this.backend, this.preferences, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final AlarmBackend backend;
  final SharedPreferences preferences;
  final DateTime Function() now;
  String? scope;
  String status = 'Avisos desactivados.';
  bool enabled = false;
  int _generation = 0;
  Future<void> _tail = Future.value();
  Map<String, dynamic> get _records =>
      jsonDecode(preferences.getString('hospital.alert.ids.v1') ?? '{}')
          as Map<String, dynamic>;
  Future<void> _save(Map<String, dynamic> records) async {
    if (!await preferences.setString(
      'hospital.alert.ids.v1',
      jsonEncode(records),
    )) {
      throw StateError('alarm_metadata_write_failed');
    }
  }

  Future<void> serialize(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.catchError((_) {});
    return result;
  }

  void reportFailure(String message) {
    status = message;
    notifyListeners();
  }

  Future<void> initialize() async {
    scope = preferences.getString('hospital.alert.scope.v1');
    if (!backend.supported) {
      status =
          'Web/computadora: avisos visuales con la hoja abierta. Cerrar el navegador detiene esos avisos.';
      return;
    }
    try {
      await backend.initialize();
      enabled = preferences.getBool('hospital.alert.enabled.v1') ?? false;
      status = enabled
          ? 'Avisos habilitados en este dispositivo; abre la hoja para actualizar horarios.'
          : 'Activa los avisos para solicitar permisos del dispositivo.';
    } catch (_) {
      status = 'No se pudieron inicializar las notificaciones.';
    }
  }

  Future<void> bind(String? newScope) async {
    if (scope == newScope) return;
    scope = newScope;
    _generation++;
    if (newScope == null) {
      await preferences.remove('hospital.alert.scope.v1');
    } else {
      await preferences.setString('hospital.alert.scope.v1', newScope);
    }
    await serialize(() async {
      final records = _records;
      for (final value in records.values) {
        await backend.cancel((value as Map)['id'] as int);
      }
      await _save({});
    });
  }

  Future<void> enable() async {
    if (!backend.supported || scope == null) return;
    try {
      status = await backend.requestPermission();
      enabled = status.startsWith('Activados');
      await preferences.setBool('hospital.alert.enabled.v1', enabled);
    } catch (_) {
      enabled = false;
      status =
          'No se pudieron activar. Revisa permisos y ajustes del dispositivo.';
    }
    if (!enabled) {
      final message = status;
      try {
        await disable();
        status = message;
      } catch (_) {
        status = '$message No se pudieron cancelar los avisos anteriores.';
      }
    }
    notifyListeners();
  }

  Future<void> disable() async {
    enabled = false;
    _generation++;
    await preferences.setBool('hospital.alert.enabled.v1', false);
    await serialize(() async {
      final records = _records;
      for (final value in records.values) {
        await backend.cancel((value as Map)['id'] as int);
      }
      await _save({});
    });
    status = 'Avisos desactivados.';
    notifyListeners();
  }

  bool get sound => preferences.getBool('hospital.alert.sound.v2') ?? true;
  bool get stockWarnings =>
      preferences.getBool('hospital.alert.stock.v2') ?? true;
  bool get vibration =>
      preferences.getBool('hospital.alert.vibration.v2') ?? true;
  int get leadMinutes => preferences.getInt('hospital.alert.lead.v2') ?? 0;
  Future<void> updateOptions({
    bool? sound,
    bool? vibration,
    bool? stockWarnings,
    int? leadMinutes,
  }) async {
    if (leadMinutes != null && ![0, 5, 10, 15, 30].contains(leadMinutes)) {
      throw const FormatException('Anticipación no válida.');
    }
    if (sound != null &&
        !await preferences.setBool('hospital.alert.sound.v2', sound)) {
      throw StateError('settings_write_failed');
    }
    if (vibration != null &&
        !await preferences.setBool('hospital.alert.vibration.v2', vibration)) {
      throw StateError('settings_write_failed');
    }
    if (leadMinutes != null &&
        !await preferences.setInt('hospital.alert.lead.v2', leadMinutes)) {
      throw StateError('settings_write_failed');
    }
    if (stockWarnings != null &&
        !await preferences.setBool('hospital.alert.stock.v2', stockWarnings)) {
      throw StateError('settings_write_failed');
    }
    notifyListeners();
  }

  Future<void> reconcile(String expectedScope, List<HospitalTask> tasks) async {
    if (scope != expectedScope || !enabled || !backend.supported) return;
    final generation = _generation;
    await serialize(() async {
      if (generation != _generation || scope != expectedScope || !enabled) {
        return;
      }
      final current = now();
      final all = planHospitalAlarms(
        tasks,
        current,
        limit: 100000,
        leadMinutes: leadMinutes,
      );
      final jobs = all.take(60).toList();
      final records = _records;
      final wanted = <String>{
        for (final job in jobs)
          jsonEncode([
            expectedScope,
            job.taskId,
            job.escalated,
            if (job.advance) 'advance',
          ]),
      };
      for (final key in records.keys.toList()) {
        if (!wanted.contains(key)) {
          await backend.cancel((records[key] as Map)['id'] as int);
          records.remove(key);
        }
      }
      for (final job in jobs) {
        if (generation != _generation || scope != expectedScope || !enabled) {
          return;
        }
        final key = jsonEncode([
          expectedScope,
          job.taskId,
          job.escalated,
          if (job.advance) 'advance',
        ]);
        final task = job.summary
            ? null
            : tasks.firstWhere((t) => t.id == job.taskId);
        final overdue = job.summary;
        final summaryIds =
            tasks
                .where(
                  (t) =>
                      t.state == HospitalTaskState.pending &&
                      !t.dueAt
                          .add(Duration(minutes: t.escalationMinutes))
                          .isAfter(current) &&
                      !(t.snoozedUntil?.isAfter(current) ?? false),
                )
                .map((t) => t.id)
                .toList()
              ..sort();
        final fingerprint = overdue
            ? 'overdue:${summaryIds.join(',')}:$sound:$vibration'
            : '${job.at.toUtc().toIso8601String()}:${task!.version}:$sound:$vibration';
        final record = records[key] as Map?;
        if (record?['fingerprint'] == fingerprint) continue;
        var id = record?['id'] as int?;
        if (id == null) {
          id = (preferences.getInt('hospital.alert.nextId.v1') ?? 1000000) + 1;
          if (id >= 2000000) throw StateError('alarm_id_capacity');
          if (!await preferences.setInt('hospital.alert.nextId.v1', id)) {
            throw StateError('alarm_id_write_failed');
          }
        }
        records[key] = {'id': id, 'fingerprint': null};
        await _save(records);
        await backend.schedule(id, job);
        records[key] = {'id': id, 'fingerprint': fingerprint};
        // Persist each successful assignment so session changes can cancel it.
        await _save(records);
      }
      await _save(records);
      status =
          'Plan local de ${jobs.length} avisos revisado.${all.length > 60 ? ' Capacidad alcanzada: abre la hoja para actualizar los siguientes.' : ''} El sonido depende de los permisos y ajustes del sistema.';
    });
    notifyListeners();
  }
}
