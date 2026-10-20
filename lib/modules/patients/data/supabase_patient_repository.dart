import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/patient_models.dart';
import '../domain/patient_activity.dart';
import '../domain/patient_repository.dart';

class SupabasePatientRepository
    implements PatientRepository, PatientActivityRepository {
  SupabasePatientRepository(this.client);
  final SupabaseClient client;
  @override
  Future<PatientActivitySnapshot> activity(String clinic) async =>
      PatientActivitySnapshot.read(
        Map<String, dynamic>.from(
          await client.rpc(
                'patient_activity_snapshot',
                params: {'p_clinic': clinic},
              )
              as Map,
        ),
        clinic,
      );

  @override
  Future<List<VetPatient>> patients(String clinicId) async {
    final rows = await client
        .from('vet_patients')
        .select()
        .eq('clinic_id', clinicId)
        .order('name');
    return rows.map(VetPatient.read).toList();
  }

  @override
  Future<List<VetOwner>> owners(String clinicId) async {
    final rows = await client
        .from('vet_owners')
        .select()
        .eq('clinic_id', clinicId)
        .order('name');
    return rows.map(VetOwner.read).toList();
  }

  @override
  Future<List<PatientEvent>> events(String clinicId, String patientId) async {
    final rows = await client
        .from('vet_patient_events')
        .select()
        .eq('clinic_id', clinicId)
        .eq('patient_id', patientId)
        .order('created_at');
    return rows.map(PatientEvent.read).toList();
  }

  @override
  Future<String> createPatient(
    String clinicId,
    Map<String, dynamic> patient,
    Map<String, dynamic>? owner,
    String operationId,
  ) async {
    return await client.rpc(
          'create_vet_patient',
          params: {
            'p_clinic_id': clinicId,
            'p_patient': patient,
            'p_owner': owner,
            'p_operation_id': operationId,
          },
        )
        as String;
  }

  @override
  Future<void> addEvent(
    String clinicId,
    String patientId,
    EventKind kind,
    Map<String, dynamic> payload,
    String operationId,
  ) async {
    await client.rpc(
      'add_vet_patient_event',
      params: {
        'p_clinic_id': clinicId,
        'p_patient_id': patientId,
        'p_kind': kind.name,
        'p_payload': validateEvent(kind, payload),
        'p_operation_id': operationId,
      },
    );
  }
}
