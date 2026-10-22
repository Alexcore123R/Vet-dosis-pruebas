import 'dart:convert';
import 'dart:typed_data';
import '../domain/preventive_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/patient_models.dart';
import '../domain/patient_activity.dart';
import '../domain/patient_repository.dart';
import '../domain/patient_contacts.dart';

class SupabasePatientRepository
    implements
        PatientRepository,
        PatientActivityRepository,
        PatientContactRepository,
        PreventiveRepository {
  SupabasePatientRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> booklet(String clinic, String patient) async {
    final raw = Map<String, dynamic>.from(
      await client.rpc(
            'preventive_booklet_snapshot',
            params: {'p_clinic': clinic, 'p_patient': patient},
          )
          as Map,
    );
    if (raw['schema_version'] != 2 ||
        raw['clinic_id'] != clinic ||
        raw['patient_id'] != patient ||
        [
          'events',
          'evidence',
          'plans',
          'retired',
          'links',
          'members',
        ].any((k) => raw[k] is! List)) {
      throw const FormatException('Carnet no compatible.');
    }
    return raw;
  }

  @override
  Future<void> attachEvidence(
    String clinic,
    String patient,
    String event,
    String label,
    Uint8List bytes,
    String mime,
    String operation,
  ) async {
    if (evidenceMime(bytes) != mime) {
      throw const FormatException('Formato del comprobante no válido.');
    }
    await client.rpc(
      'preventive_evidence_add',
      params: {
        'p_clinic': clinic,
        'p_patient': patient,
        'p_event': event,
        'p_label': label,
        'p_mime': mime,
        'p_content': base64Encode(bytes),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<Uint8List> evidence(
    String clinic,
    String patient,
    String attachment,
  ) async {
    final raw = Map<String, dynamic>.from(
      await client.rpc(
            'preventive_evidence_get',
            params: {
              'p_clinic': clinic,
              'p_patient': patient,
              'p_id': attachment,
            },
          )
          as Map,
    );
    final bytes = base64Decode(raw['content'] as String);
    if (evidenceMime(bytes) != raw['mime']) {
      throw const FormatException('Comprobante no válido.');
    }
    return bytes;
  }

  @override
  Future<void> planPreventive(
    String clinic,
    String patient,
    Map<String, dynamic> data,
    String operation,
  ) async {
    calendarDate(textField(data, 'due_date', required: true));
    await client.rpc(
      'preventive_plan_add',
      params: {
        'p_clinic': clinic,
        'p_patient': patient,
        'p_data': data,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> retirePlan(
    String clinic,
    String patient,
    String plan,
    String reason,
    String operation,
  ) async {
    await client.rpc(
      'preventive_plan_retire',
      params: {
        'p_clinic': clinic,
        'p_patient': patient,
        'p_plan': plan,
        'p_reason': reason,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> schedulePreventive(
    String clinic,
    String patient,
    String plan,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'preventive_plan_schedule',
      params: {
        'p_clinic': clinic,
        'p_patient': patient,
        'p_plan': plan,
        'p_data': data,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> contact(String clinic, String patient) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'patient_contact_snapshot',
              params: {'p_clinic': clinic, 'p_patient': patient},
            )
            as Map,
      );
  @override
  Future<void> saveContact(
    String clinic,
    String patient,
    String owner,
    int version,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'patient_contact_save',
      params: {
        'p_clinic': clinic,
        'p_patient': patient,
        'p_owner': owner,
        'p_version': version,
        'p_data': validateContact(data),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> logContact(
    String clinic,
    String patient,
    String owner,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'patient_contact_log',
      params: {
        'p_clinic': clinic,
        'p_patient': patient,
        'p_owner': owner,
        'p_data': data,
        'p_operation': operation,
      },
    );
  }

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
