import 'dart:convert';
import 'dart:typed_data';
import 'backup_archive.dart';

/// A read-only recovery inspection, never an executable SQL/import instruction.
class BackupRecoveryReport {
  BackupRecoveryReport._(
    this.clinic,
    this.serverAt,
    this.tables,
    this.excluded,
  );
  final String clinic, serverAt;
  final Map<String, int> tables;
  final List<String> excluded;
  int get records => tables.values.fold(0, (sum, count) => sum + count);
  static BackupRecoveryReport inspect(
    Uint8List archive,
    String expectedClinic,
  ) {
    final snapshot = BackupArchive.verify(archive);
    if (snapshot['clinic_id'] != expectedClinic) {
      throw const FormatException(
        'Este archivo corresponde a otra clínica. Abre su espacio autorizado para revisarlo.',
      );
    }
    if (snapshot['format'] != 'vetdosis-operational-backup' ||
        snapshot['version'] != 1) {
      throw const FormatException('No es un respaldo operacional compatible.');
    }
    final source = snapshot['tables'] as Map;
    final counts = <String, int>{};
    for (final entry in source.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Una tabla del respaldo no es válida.');
      }
      final ids = <String>{};
      for (final row in entry.value as List) {
        if (row is! Map) {
          throw const FormatException('Una fila del respaldo no es válida.');
        }
        if (row['clinic_id'] != null && row['clinic_id'] != expectedClinic) {
          throw const FormatException(
            'El archivo mezcla registros de distintas clínicas.',
          );
        }
        // Global catalogs/base versions can be shared; clinic rows cannot.
        if (row['id'] != null && !ids.add('${row['id']}')) {
          throw FormatException(
            'Hay identificadores repetidos en ${entry.key}.',
          );
        }
      }
      counts[entry.key as String] = (entry.value as List).length;
    }
    final scope = snapshot['scope'];
    final raw = scope is Map ? scope['excluded'] : null;
    return BackupRecoveryReport._(
      expectedClinic,
      '${snapshot['server_at'] ?? 'Fecha no registrada'}',
      counts,
      raw is List ? raw.map((v) => v.toString()).toList() : [],
    );
  }

  String toJson() => const JsonEncoder.withIndent('  ').convert({
    'format': 'vetdosis-recovery-inspection',
    'version': 1,
    'clinic_id': clinic,
    'server_at': serverAt,
    'record_count': records,
    'tables': tables,
    'excluded': excluded,
    'restored': false,
    'scope':
        'Inspección sin cambios en la base de datos; no acredita origen ni restaurabilidad completa.',
  });
}
