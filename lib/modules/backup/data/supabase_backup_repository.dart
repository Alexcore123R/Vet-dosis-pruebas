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
  Future<Map<String, dynamic>> previewRestoreConflicts(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required String manifestSha256,
    required Map<String, List<String>> manifest,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
      'restore_preview_conflicts',
      params: {
        'p_clinic': clinic,
        'p_stage': stageId,
        'p_archive_sha256': archiveSha256,
        'p_manifest_sha256': manifestSha256,
        'p_manifest': manifest,
      },
    ) as Map,
  );

  @override
  Future<Map<String, dynamic>> previewRestorePlan(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required String conflictManifestSha256,
    required String dependencyManifestSha256,
    required Map<String, Map<String, List<Map<String, String>>>> dependencies,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
      'restore_preview_plan',
      params: {
        'p_clinic': clinic,
        'p_stage': stageId,
        'p_archive_sha256': archiveSha256,
        'p_conflict_manifest_sha256': conflictManifestSha256,
        'p_dependency_manifest_sha256': dependencyManifestSha256,
        'p_dependencies': dependencies,
      },
    ) as Map,
  );

  @override
  Future<Map<String, dynamic>> preflightRestore(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required String conflictManifestSha256,
    required String dependencyManifestSha256,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
      'restore_preview_preflight',
      params: {
        'p_clinic': clinic,
        'p_stage': stageId,
        'p_archive_sha256': archiveSha256,
        'p_conflict_manifest_sha256': conflictManifestSha256,
        'p_dependency_manifest_sha256': dependencyManifestSha256,
      },
    ) as Map,
  );

  @override
  Future<Map<String, dynamic>> prepareRestoreOwners(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required List<Map<String, dynamic>> owners,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
      'restore_prepare_owners',
      params: {
        'p_clinic': clinic,
        'p_stage': stageId,
        'p_archive_sha256': archiveSha256,
        'p_owners': owners,
      },
    ) as Map,
  );

  @override
  Future<Map<String, dynamic>> applyRestoreOwners(
    String clinic, {
    required String stageId,
    required String preflightId,
    required String ownerPayloadSha256,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
      'restore_apply_owners',
      params: {
        'p_clinic': clinic,
        'p_stage': stageId,
        'p_preflight': preflightId,
        'p_owner_payload_sha256': ownerPayloadSha256,
      },
    ) as Map,
  );

  @override
  Future<Map<String, dynamic>> prepareRestorePatients(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required List<Map<String, dynamic>> patients,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
      'restore_prepare_patients',
      params: {
        'p_clinic': clinic,
        'p_stage': stageId,
        'p_archive_sha256': archiveSha256,
        'p_patients': patients,
      },
    ) as Map,
  );

  @override
  Future<Map<String, dynamic>> applyRestorePatients(
    String clinic, {
    required String stageId,
    required String preflightId,
    required String patientPayloadSha256,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
      'restore_apply_patients',
      params: {
        'p_clinic': clinic,
        'p_stage': stageId,
        'p_preflight': preflightId,
        'p_patient_payload_sha256': patientPayloadSha256,
      },
    ) as Map,
  );

  @override
  Future<void> discardRestorePreview(String clinic, String stageId) async {
    await client.rpc(
      'restore_preview_discard',
      params: {'p_clinic': clinic, 'p_stage': stageId},
    );
  }
}
