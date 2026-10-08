import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/hospital_models.dart';
import '../domain/hospital_repository.dart';

class SupabaseHospitalRepository implements HospitalRepository {
  SupabaseHospitalRepository(this.client);
  final SupabaseClient client;
  @override
  Future<HospitalSnapshot> load(String clinicId) async {
    final raw =
        await client.rpc('hospital_snapshot', params: {'p_clinic_id': clinicId})
            as Map;
    return HospitalSnapshot(
      (raw['stays'] as List)
          .map((r) => HospitalStay.read(Map<String, dynamic>.from(r as Map)))
          .toList(),
      (raw['tasks'] as List)
          .map((r) => HospitalTask.read(Map<String, dynamic>.from(r as Map)))
          .toList(),
    );
  }

  @override
  Future<void> admit(
    String clinicId,
    String patientId,
    String cage,
    String operationId,
  ) async {
    await client.rpc(
      'hospital_admit',
      params: {
        'p_clinic_id': clinicId,
        'p_patient_id': patientId,
        'p_cage': cage,
        'p_operation_id': operationId,
      },
    );
  }

  @override
  Future<void> prescribe(
    String clinicId,
    String stayId,
    String kind,
    String label,
    String instructions,
    List<DateTime> times,
    int escalationMinutes,
    String operationId,
  ) async {
    await client.rpc(
      'hospital_prescribe',
      params: {
        'p_clinic_id': clinicId,
        'p_stay_id': stayId,
        'p_kind': kind,
        'p_label': label,
        'p_instructions': instructions,
        'p_times': times.map((t) => t.toUtc().toIso8601String()).toList(),
        'p_escalation_minutes': escalationMinutes,
        'p_operation_id': operationId,
      },
    );
  }

  Future<void> transition(
    String action,
    String clinicId,
    HospitalTask task, {
    int? minutes,
    String? reason,
  }) async {
    await client.rpc(
      'hospital_task_action',
      params: {
        'p_clinic_id': clinicId,
        'p_task_id': task.id,
        'p_expected_version': task.version,
        'p_action': action,
        'p_minutes': minutes,
        'p_reason': reason,
      },
    );
  }

  @override
  Future<void> perform(String clinicId, HospitalTask task) =>
      transition('perform', clinicId, task);
  @override
  Future<void> snooze(
    String clinicId,
    HospitalTask task,
    int minutes,
    String reason,
  ) => transition('snooze', clinicId, task, minutes: minutes, reason: reason);
  @override
  Future<void> cancel(String clinicId, HospitalTask task, String reason) =>
      transition('cancel', clinicId, task, reason: reason);
  @override
  Future<void> discharge(
    String clinicId,
    HospitalStay stay,
    String reason,
  ) async {
    await client.rpc(
      'hospital_discharge',
      params: {
        'p_clinic_id': clinicId,
        'p_stay_id': stay.id,
        'p_expected_version': stay.version,
        'p_reason': reason,
      },
    );
  }
}
