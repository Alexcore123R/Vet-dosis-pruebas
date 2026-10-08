import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../forms/domain/form_models.dart';
import '../domain/prescribing_repository.dart';

class SupabasePrescribingRepository implements PrescribingRepository {
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
    'rx_hospital',
  };
  static const writes = {
    'rx_profile_save',
    'rx_delegate',
    'rx_delegate_revoke',
    'rx_create',
    'rx_save',
    'rx_prepare',
    'rx_finalize',
    'rx_vial_open',
    'rx_vial_close',
    'rx_vial_adjust',
    'rx_medication_report',
    'rx_medication_review',
    'rx_report_create',
    'rx_report_finalize',
    'rx_schedule',
  };
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
