import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/operations_repository.dart';

class SupabaseOperationsRepository
    implements OperationsRepository, AppointmentPatientRepository {
  SupabaseOperationsRepository(this.client);
  final SupabaseClient client;
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
