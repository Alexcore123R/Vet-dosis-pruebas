import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/operations_repository.dart';
import '../domain/appointment_links.dart';
import '../domain/appointment_care.dart';

class SupabaseOperationsRepository
    implements
        OperationsRepository,
        AppointmentPatientRepository,
        AppointmentLinksRepository,
        AppointmentCareRepository {
  SupabaseOperationsRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> careSnapshot(
    String clinic,
    List<String> ids,
  ) async {
    final rows = <dynamic>[];
    Map<String, dynamic>? result;
    final unique = ids.toSet().toList();
    for (var offset = 0; offset < unique.length || offset == 0; offset += 100) {
      final batch = unique.skip(offset).take(100).toList();
      final raw = Map<String, dynamic>.from(
        await client.rpc(
              'appointment_care_snapshot',
              params: {'p_clinic': clinic, 'p_appointments': batch},
            )
            as Map,
      );
      if (raw['schema_version'] != 1 ||
          raw['clinic_id'] != clinic ||
          raw['appointments'] is! List ||
          DateTime.tryParse('${raw['day_start']}') == null ||
          DateTime.tryParse('${raw['day_end']}') == null) {
        throw const FormatException('Contrato de atención no compatible.');
      }
      if (result != null && result['day'] != raw['day']) {
        throw const FormatException('Cambió el día de la clínica. Actualiza.');
      }
      for (final row in raw['appointments'] as List) {
        if (row is! Map || !batch.contains(row['appointment_id'])) {
          throw const FormatException('Cita no solicitada.');
        }
        rows.add(row);
      }
      result = raw;
    }
    return {...result!, 'appointments': rows};
  }

  @override
  Future<void> careWrite(
    String clinic,
    String appointment,
    int version,
    String action,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'appointment_care_write',
      params: {
        'p_clinic': clinic,
        'p_appointment': appointment,
        'p_version': version,
        'p_action': action,
        'p_data': validateCare(action, data),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<Map<String, Map<String, dynamic>>> patientLinks(
    String clinic,
    List<String> appointments,
  ) async {
    final output = <String, Map<String, dynamic>>{};
    final unique = appointments.toSet().toList();
    for (var offset = 0; offset < unique.length; offset += 100) {
      final batch = unique.skip(offset).take(100).toList();
      final raw = Map<String, dynamic>.from(
        await client.rpc(
              'appointment_patient_links',
              params: {'p_clinic': clinic, 'p_appointments': batch},
            )
            as Map,
      );
      if (raw['schema_version'] != 1 ||
          raw['clinic_id'] != clinic ||
          raw['appointments'] is! List) {
        throw const FormatException(
          'Contrato de contactos y cobros no compatible.',
        );
      }
      for (final item in raw['appointments'] as List) {
        final row = Map<String, dynamic>.from(item as Map);
        final id = row['appointment_id'] as String;
        if (!batch.contains(id)) {
          throw const FormatException('Cita no solicitada.');
        }
        output[id] = row;
      }
    }
    return output;
  }

  @override
  Future<List<Map<String, dynamic>>> searchPatients(
    String clinic,
    String query,
  ) async =>
      (await client.rpc(
                'ops_patient_search',
                params: {'p_clinic': clinic, 'p_query': query},
              )
              as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('ops_dashboard', params: {'p_clinic': clinic}) as Map,
      );
  @override
  Future<void> write(
    String clinic,
    String action,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'ops_write',
      params: {
        'p_clinic': clinic,
        'p_action': action,
        'p_data': data,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> medical(
    String clinic, {
    Map<String, dynamic>? details,
    bool consent = false,
  }) async =>
      (await client.rpc(
                'ops_medical',
                params: {
                  'p_clinic': clinic,
                  'p_details': details,
                  'p_consent': consent,
                },
              )
              as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
}
