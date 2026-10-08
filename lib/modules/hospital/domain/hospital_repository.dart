import 'hospital_models.dart';

abstract interface class HospitalRepository {
  Future<HospitalSnapshot> load(String clinicId);
  Future<void> admit(
    String clinicId,
    String patientId,
    String cage,
    String operationId,
  );
  Future<void> prescribe(
    String clinicId,
    String stayId,
    String kind,
    String label,
    String instructions,
    List<DateTime> times,
    int escalationMinutes,
    String operationId,
  );
  Future<void> perform(String clinicId, HospitalTask task);
  Future<void> snooze(
    String clinicId,
    HospitalTask task,
    int minutes,
    String reason,
  );
  Future<void> cancel(String clinicId, HospitalTask task, String reason);
  Future<void> discharge(String clinicId, HospitalStay stay, String reason);
}
