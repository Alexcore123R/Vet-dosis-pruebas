import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/inventory_repository.dart';

class SupabaseInventoryRepository
    implements
        InventoryRepository,
        DispensingPermissionRepository,
        InventoryManagementRepository {
  SupabaseInventoryRepository(this.client);
  final SupabaseClient client;
  static const reads = {
    'inv_dashboard',
    'inv_ai_insights',
    'ops_dashboard',
    'pay_dashboard',
    'inv_shift_snapshot',
    'rx_vials',
    'inv_workflow_dashboard',
    'inv_delivery_items',
    'inv_billable_services',
    'inv_catalog_services',
    'inv_invoice_requests',
  };
  static const writes = {
    'inv_settings',
    'pay_report',
    'pay_reconcile',
    'inv_delivery_grant',
    'inv_delivery_revoke',
    'inv_application_tariff',
    'inv_application_prepare',
    'inv_delivery_prepare',
    'inv_dispensing_authorize',
    'inv_product_save',
    'inv_enable_legacy',
    'inv_lot_receive',
    'inv_stock_adjust',
    'inv_shift_open',
    'inv_sale_post',
    'inv_catalog_service_sale_post',
    'inv_invoice_request',
    'inv_sale_reverse',
    'inv_cash_move',
    'inv_shift_close',
    'inv_order_draft',
    'inv_order_approve',
    'inv_vial_link',
  };
  @override
  Future<Map<String, dynamic>?> dispensingPermissions(String clinic) async {
    try {
      return Map<String, dynamic>.from(
        await client.rpc(
              'inv_dispensing_permissions',
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
  Future<Map<String, dynamic>?> managementPermissions(String clinic) async {
    try {
      return Map<String, dynamic>.from(
        await client.rpc(
              'inv_management_permissions',
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
  Future<void> photo(
    String clinic,
    String product,
    int version,
    Uint8List bytes,
    String extension,
  ) async {
    if (bytes.isEmpty ||
        bytes.length > 4 * 1024 * 1024 ||
        !['jpg', 'png'].contains(extension)) {
      throw const FormatException('Foto JPEG/PNG de máximo 4 MB.');
    }
    final path = '$clinic/$product/${newOperationId()}.$extension';
    await client.storage
        .from('inventory-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
            upsert: false,
          ),
        );
    await client.rpc(
      'inv_photo_attach',
      params: {'p_item': product, 'p_version': version, 'p_path': path},
    );
  }

  @override
  Future<String> photoUrl(String path) =>
      client.storage.from('inventory-photos').createSignedUrl(path, 60);
}
