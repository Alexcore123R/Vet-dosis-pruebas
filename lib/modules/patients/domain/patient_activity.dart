import 'patient_models.dart';

enum PatientActivityKind {
  hospitalized('Hospitalizados'),
  consultation('En atención'),
  service('En servicio'),
  ready('Pendientes de entrega');

  const PatientActivityKind(this.label);
  final String label;
}

class PatientActivity {
  const PatientActivity({
    required this.patientId,
    required this.recordId,
    required this.kind,
    required this.detail,
    required this.localTime,
    required this.responsible,
  });
  final String patientId, recordId, detail, localTime, responsible;
  final PatientActivityKind kind;
  String get destination =>
      kind == PatientActivityKind.hospitalized ? 'Hospitalización' : 'Agenda';
}

class PatientActivitySnapshot {
  const PatientActivitySnapshot({
    required this.day,
    required this.timezone,
    required this.serverTime,
    required this.hospitalAllowed,
    required this.appointmentsAllowed,
    required this.items,
  });
  final String day, timezone;
  final DateTime serverTime;
  final bool hospitalAllowed, appointmentsAllowed;
  final List<PatientActivity> items;

  factory PatientActivitySnapshot.read(
    Map<String, dynamic> data,
    String clinic,
  ) {
    if (data['schema_version'] != 1 ||
        data['clinic_id'] != clinic ||
        data['hospital_allowed'] is! bool ||
        data['appointments_allowed'] is! bool ||
        data['items'] is! List ||
        data['timezone'] is! String ||
        (data['timezone'] as String).isEmpty ||
        data['server_time'] is! String) {
      throw const FormatException('Actividad no disponible con este contrato.');
    }
    final day = calendarDate(data['day'] as String);
    final rows = <PatientActivity>[];
    for (final raw in data['items'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final kind = PatientActivityKind.values.byName(row['kind'] as String);
      if ((kind == PatientActivityKind.hospitalized &&
              data['hospital_allowed'] != true) ||
          (kind != PatientActivityKind.hospitalized &&
              data['appointments_allowed'] != true)) {
        throw const FormatException('Actividad fuera de permisos.');
      }
      for (final field in [
        'patient_id',
        'record_id',
        'detail',
        'local_time',
        'responsible',
      ]) {
        if (row[field] is! String) {
          throw const FormatException('Actividad inválida.');
        }
      }
      rows.add(
        PatientActivity(
          patientId: row['patient_id'] as String,
          recordId: row['record_id'] as String,
          kind: kind,
          detail: row['detail'] as String,
          localTime: row['local_time'] as String,
          responsible: row['responsible'] as String,
        ),
      );
    }
    return PatientActivitySnapshot(
      day: day,
      timezone: data['timezone'] as String,
      serverTime: DateTime.parse(data['server_time'] as String),
      hospitalAllowed: data['hospital_allowed'] as bool,
      appointmentsAllowed: data['appointments_allowed'] as bool,
      items: List.unmodifiable(rows),
    );
  }

  List<PatientActivity> forPatient(String id) =>
      items.where((a) => a.patientId == id).toList();
  int count(PatientActivityKind kind, Set<String> visiblePatients) => items
      .where((a) => a.kind == kind && visiblePatients.contains(a.patientId))
      .map((a) => a.patientId)
      .toSet()
      .length;
  bool allowed(PatientActivityKind kind) =>
      kind == PatientActivityKind.hospitalized
      ? hospitalAllowed
      : appointmentsAllowed;
}

abstract interface class PatientActivityRepository {
  Future<PatientActivitySnapshot> activity(String clinic);
}
