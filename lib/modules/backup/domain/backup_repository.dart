import 'dart:typed_data';

abstract class BackupRepository {
  Future<Map<String, dynamic>> workspace(String clinic);
  Future<Map<String, dynamic>> statistics(String clinic);
  Future<String> snapshot(String clinic, {required BackupScope scope});
  Future<Uint8List> photo(String path);
  Future<Map<String, dynamic>> stageRestorePreview(
    String clinic, {
    required String format,
    required int version,
    required String archiveSha256,
    required DateTime? sourceServerAt,
    required Map<String, int> tableCounts,
  });
  Future<Map<String, dynamic>> restorePreview(String clinic);
  Future<Map<String, dynamic>> previewRestoreConflicts(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required String manifestSha256,
    required Map<String, List<String>> manifest,
  });
  Future<Map<String, dynamic>> previewRestorePlan(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required String conflictManifestSha256,
    required String dependencyManifestSha256,
    required Map<String, Map<String, List<Map<String, String>>>> dependencies,
  });
  Future<Map<String, dynamic>> preflightRestore(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required String conflictManifestSha256,
    required String dependencyManifestSha256,
  });
  Future<Map<String, dynamic>> prepareRestoreOwners(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required List<Map<String, dynamic>> owners,
  });
  Future<Map<String, dynamic>> applyRestoreOwners(
    String clinic, {
    required String stageId,
    required String preflightId,
    required String ownerPayloadSha256,
  });
  Future<Map<String, dynamic>> prepareRestorePatients(
    String clinic, {
    required String stageId,
    required String archiveSha256,
    required List<Map<String, dynamic>> patients,
  });
  Future<Map<String, dynamic>> applyRestorePatients(
    String clinic, {
    required String stageId,
    required String preflightId,
    required String patientPayloadSha256,
  });
  Future<void> discardRestorePreview(String clinic, String stageId);
}

enum BackupScope { clinic, personal }

class BackupAccess {
  const BackupAccess({
    required this.clinic,
    required this.personal,
    required this.statistics,
    required this.workspaceKind,
    this.restorePreview = false,
    this.restoreApplyTest = false,
  });

  final bool clinic, personal, statistics, restorePreview, restoreApplyTest;
  final String workspaceKind;

  factory BackupAccess.read(Map<String, dynamic> value) {
    final exports = value['exports'];
    if (value['schema_version'] != 1 ||
        value['mode'] != 'explicit_backup' ||
        exports is! Map ||
        exports['clinic'] is! bool ||
        exports['personal'] is! bool ||
        value['statistics'] is! bool ||
        !{'clinic', 'personal'}.contains(value['workspace_kind'])) {
      throw const FormatException('Contrato de respaldo desconocido.');
    }
    return BackupAccess(
      clinic: exports['clinic'] as bool,
      personal: exports['personal'] as bool,
      statistics: value['statistics'] as bool,
      workspaceKind: value['workspace_kind'] as String,
      restorePreview: value['restore_preview'] == true,
      restoreApplyTest: value['restore_apply_test'] == true,
    );
  }
}
