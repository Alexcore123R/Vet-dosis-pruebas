import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../forms/domain/form_models.dart';
import '../domain/prescribing_repository.dart';

class SupabasePrescribingRepository
    implements
        PrescribingRepository,
        MedicationPermissionRepository,
        PrescriptionPermissionRepository,
        ReportPermissionRepository {
  SupabasePrescribingRepository(this.client);
  final SupabaseClient client;
  static const reads = {
    'rx_profiles',
    'rx_delegations',
    'rx_list',
    'rx_snapshot',
    'rx_vials',
    'rx_medications',
    'rx_reports',
    'rx_report_export',
    'rx_hospital',
    'rx_consultations',
    'rx_standing_workspace',
  };
  static const writes = {
    'rx_profile_save',
    'rx_delegate',
    'rx_delegate_revoke',
    'rx_create',
    'rx_save',
    'rx_prepare',
    'rx_consultation_sign',
    'rx_prepare_attributed',
    'rx_authorize_individual',
    'rx_return_to_draft',
    'rx_finalize',
    'rx_standing_offer',
    'rx_standing_accept',
    'rx_prepare_standing',
    'rx_standing_resume',
    'rx_standing_review',
    'rx_vial_open',
    'rx_vial_close',
    'rx_vial_adjust',
    'rx_medication_report',
    'rx_medication_review',
    'rx_report_create',
    'rx_report_finalize',
    'rx_schedule',
    'rx_schedule_typed',
  };
  @override
  Future<Map<String, dynamic>?> reportPermissions(String clinic) async {
    try {
      return Map<String, dynamic>.from(
        await client.rpc('rx_report_permissions', params: {'p_clinic': clinic})
            as Map,
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> prescriptionPermissions(String clinic) async {
    try {
      return Map<String, dynamic>.from(
        await client.rpc(
              'rx_prescription_permissions',
              params: {'p_clinic': clinic},
            )
            as Map,
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> medicationPermissions(
    String clinic,
    String? caseId,
  ) async {
    try {
      return Map<String, dynamic>.from(
        await client.rpc(
              'rx_operational_permissions',
              params: {'p_clinic': clinic, 'p_case': caseId},
            )
            as Map,
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) {
    if (!reads.contains(command)) throw ArgumentError('Consulta no disponible');
    return client.rpc(command, params: args);
  }

  @override
  Future<dynamic> write(String command, Map<String, dynamic> args) {
    if (!writes.contains(command)) {
      throw ArgumentError('Operación no disponible');
    }
    return client.rpc(command, params: args);
  }

  @override
  Future<List<Map<String, dynamic>>> products() async {
    final rows = await client
        .from('medication_product_versions')
        .select()
        .order('version', ascending: false);
    final keys = <String>{};
    return rows
        .where((r) => keys.add(r['product_key'] as String))
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  @override
  Future<ReviewedPdf> pdf(String kind, String id) async {
    final response = await client.functions.invoke(
      'forms-pdf',
      body: {'action': 'rx', 'kind': kind, 'id': id},
    );
    final data = Map<String, dynamic>.from(response.data);
    return ReviewedPdf(
      Uint8List.fromList(
        base64Decode((data['pdf'] as String).replaceAll(RegExp(r'\s'), '')),
      ),
      data['hash'],
    );
  }
}
