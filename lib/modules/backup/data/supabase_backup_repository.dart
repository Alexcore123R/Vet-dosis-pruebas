import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/backup_repository.dart';

class SupabaseBackupRepository implements BackupRepository {
  SupabaseBackupRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> workspace(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('backup_workspace', params: {'p_clinic': clinic})
            as Map,
      );
  @override
  Future<Map<String, dynamic>> statistics(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('clinic_statistics', params: {'p_clinic': clinic})
            as Map,
      );
  @override
  Future<String> snapshot(String clinic, {required BackupScope scope}) async =>
      await client.rpc(
            scope == BackupScope.clinic ? 'clinic_export' : 'personal_export',
            params: {'p_clinic': clinic},
          )
          as String;
  @override
  Future<Uint8List> photo(String path) =>
      client.storage.from('inventory-photos').download(path);

  @override
  Future<Map<String, dynamic>> stageRestorePreview(
    String clinic, {
    required String format,
    required int version,
    required String archiveSha256,
    required DateTime? sourceServerAt,
    required Map<String, int> tableCounts,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
      'restore_preview_stage',
      params: {
        'p_clinic': clinic,
        'p_format': format,
        'p_version': version,
        'p_archive_sha256': archiveSha256,
        'p_source_server_at': sourceServerAt?.toUtc().toIso8601String(),
        'p_table_counts': tableCounts,
      },
    ) as Map,
  );

  @override
  Future<Map<String, dynamic>> restorePreview(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('restore_preview_get', params: {'p_clinic': clinic})
            as Map,
      );

  @override
  Future<void> discardRestorePreview(String clinic, String stageId) async {
    await client.rpc(
      'restore_preview_discard',
      params: {'p_clinic': clinic, 'p_stage': stageId},
    );
  }
}
