import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/backup_repository.dart';

class SupabaseBackupRepository implements BackupRepository {
  SupabaseBackupRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> statistics(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('clinic_statistics', params: {'p_clinic': clinic})
            as Map,
      );
  @override
  Future<String> snapshot(String clinic) async =>
      await client.rpc('clinic_export', params: {'p_clinic': clinic}) as String;
  @override
  Future<Uint8List> photo(String path) =>
      client.storage.from('inventory-photos').download(path);
}
