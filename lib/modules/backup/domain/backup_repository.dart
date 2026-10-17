import 'dart:typed_data';

abstract class BackupRepository {
  Future<Map<String, dynamic>> workspace(String clinic);
  Future<Map<String, dynamic>> statistics(String clinic);
  Future<String> snapshot(String clinic, {required BackupScope scope});
  Future<Uint8List> photo(String path);
}

enum BackupScope { clinic, personal }

class BackupAccess {
  const BackupAccess({
    required this.clinic,
    required this.personal,
    required this.statistics,
    required this.workspaceKind,
  });

  final bool clinic, personal, statistics;
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
    );
  }
}
