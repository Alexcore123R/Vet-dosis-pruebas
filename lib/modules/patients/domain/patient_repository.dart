import 'patient_models.dart';

abstract interface class PatientRepository {
  Future<List<VetPatient>> patients(String clinicId);
  Future<List<VetOwner>> owners(String clinicId);
  Future<List<PatientEvent>> events(String clinicId, String patientId);
  Future<String> createPatient(
    String clinicId,
    Map<String, dynamic> patient,
    Map<String, dynamic>? owner,
    String operationId,
  );
  Future<void> addEvent(
    String clinicId,
    String patientId,
    EventKind kind,
    Map<String, dynamic> payload,
    String operationId,
  );
}
