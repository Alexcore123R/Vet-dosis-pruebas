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
  });

  final bool clinic, personal, statistics, restorePreview;
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
    );
  }
}
