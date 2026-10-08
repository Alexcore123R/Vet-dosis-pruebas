import '../../auth/domain/clinic_membership.dart';

class HospitalAccess {
  const HospitalAccess(this.role);
  final ClinicRole role;
  bool get clinical =>
      [ClinicRole.admin, ClinicRole.mvz, ClinicRole.auxiliar].contains(role);
  bool get prescribe => [ClinicRole.admin, ClinicRole.mvz].contains(role);
}

class HospitalStay {
  const HospitalStay({
    required this.id,
    required this.clinicId,
    required this.patientId,
    required this.patientName,
    required this.species,
    required this.cage,
    required this.admittedAt,
    required this.version,
  });
  final String id, clinicId, patientId, patientName, species, cage;
  final DateTime admittedAt;
  final int version;
  factory HospitalStay.read(Map<String, dynamic> m) {
    final patient = m['vet_patients'] as Map;
    return HospitalStay(
      id: m['id'] as String,
      clinicId: m['clinic_id'] as String,
      patientId: m['patient_id'] as String,
      patientName: patient['name'] as String,
      species: patient['species'] as String,
      cage: m['cage'] as String,
      admittedAt: DateTime.parse(m['admitted_at'] as String),
      version: m['version'] as int,
    );
  }
}

enum HospitalTaskState { pending, done, cancelled }

enum TaskUrgency { scheduled, due, snoozed, escalated, done, cancelled }

class HospitalTask {
  const HospitalTask({
    required this.id,
    required this.stayId,
    required this.kind,
    required this.label,
    required this.instructions,
    required this.dueAt,
    required this.escalationMinutes,
    required this.state,
    required this.version,
    this.snoozedUntil,
    this.performedAt,
    this.performedBy,
    this.prescriptionItemId,
    this.clinicalCaseId,
    this.medicationRecordId,
    this.snoozeCount = 0,
  });
  final String id, stayId, kind, label, instructions;
  final DateTime dueAt;
  final int escalationMinutes, version, snoozeCount;
  final HospitalTaskState state;
  final DateTime? snoozedUntil, performedAt;
  final String? performedBy;
  final String? prescriptionItemId, clinicalCaseId, medicationRecordId;
  factory HospitalTask.read(Map<String, dynamic> m) => HospitalTask(
    id: m['id'] as String,
    stayId: m['stay_id'] as String,
    kind: m['kind'] as String,
    label: m['label'] as String,
    instructions: m['instructions'] as String,
    dueAt: DateTime.parse(m['due_at'] as String),
    escalationMinutes: m['escalation_minutes'] as int,
    state: HospitalTaskState.values.byName(m['state'] as String),
    version: m['version'] as int,
    snoozeCount: m['snooze_count'] as int,
    snoozedUntil: m['snoozed_until'] == null
        ? null
        : DateTime.parse(m['snoozed_until'] as String),
    performedAt: m['performed_at'] == null
        ? null
        : DateTime.parse(m['performed_at'] as String),
    performedBy: m['performed_by'] as String?,
    prescriptionItemId: m['prescription_item_id'] as String?,
    clinicalCaseId: m['clinical_case_id'] as String?,
    medicationRecordId: m['medication_record_id'] as String?,
  );
  TaskUrgency urgency(DateTime now) {
    if (state == HospitalTaskState.done) return TaskUrgency.done;
    if (state == HospitalTaskState.cancelled) return TaskUrgency.cancelled;
    if (now.isBefore(dueAt)) return TaskUrgency.scheduled;
    if (!now.isBefore(dueAt.add(Duration(minutes: escalationMinutes)))) {
      return TaskUrgency.escalated;
    }
    if (snoozedUntil?.isAfter(now) ?? false) return TaskUrgency.snoozed;
    return TaskUrgency.due;
  }
}

class HospitalSnapshot {
  const HospitalSnapshot(this.stays, this.tasks);
  final List<HospitalStay> stays;
  final List<HospitalTask> tasks;
}

List<DateTime> validateSchedule(List<DateTime> times, {required DateTime now}) {
  if (times.isEmpty || times.length > 200) {
    throw const FormatException('Indica entre 1 y 200 horarios.');
  }
  final sorted = times.map((t) => t.toUtc()).toList()..sort();
  if (sorted.any((t) => !t.isAfter(now))) {
    throw const FormatException(
      'Los nuevos horarios deben estar en el futuro.',
    );
  }
  if (sorted.map((t) => t.millisecondsSinceEpoch).toSet().length !=
      sorted.length) {
    throw const FormatException('Hay horarios repetidos.');
  }
  return List.unmodifiable(sorted);
}

String hospitalText(String value, {int max = 300}) {
  final t = value.trim();
  if (t.isEmpty || t.length > max) {
    throw const FormatException(
      'Completa los campos y respeta su longitud máxima.',
    );
  }
  return t;
}

class AlarmJob {
  const AlarmJob(this.taskId, this.at, this.escalated, {this.summary = false});
  final String taskId;
  final DateTime at;
  final bool escalated;
  final bool summary;
}

List<AlarmJob> planHospitalAlarms(
  List<HospitalTask> tasks,
  DateTime now, {
  int limit = 60,
}) {
  final jobs = <AlarmJob>[];
  bool overdue = false;
  for (final task in tasks.where((t) => t.state == HospitalTaskState.pending)) {
    final originalEscalation = task.dueAt.add(
      Duration(minutes: task.escalationMinutes),
    );
    final next = task.snoozedUntil?.isAfter(task.dueAt) == true
        ? task.snoozedUntil!
        : task.dueAt;
    final escalation = next.isAfter(originalEscalation)
        ? next
        : originalEscalation;
    if (next.isAfter(now)) {
      jobs.add(AlarmJob(task.id, next, !next.isBefore(originalEscalation)));
    }
    if (escalation.isAfter(now) && escalation != next) {
      jobs.add(AlarmJob(task.id, escalation, true));
    }
    // Already overdue: a generic reminder shortly after reconciliation, never a
    // prescription or an automatic administration. IDs replace the same alert.
    if (!escalation.isAfter(now)) {
      overdue = true;
    }
  }
  if (overdue) {
    jobs.add(
      AlarmJob(
        'overdue-summary',
        now.add(const Duration(seconds: 2)),
        true,
        summary: true,
      ),
    );
  }
  jobs.sort((a, b) {
    final time = a.at.compareTo(b.at);
    return time == 0 ? a.taskId.compareTo(b.taskId) : time;
  });
  return List.unmodifiable(jobs.take(limit));
}
