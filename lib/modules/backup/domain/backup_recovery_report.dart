import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'backup_archive.dart';

/// A read-only recovery inspection, never an executable SQL/import instruction.
class BackupRecoveryReport {
  BackupRecoveryReport._(
    this.clinic,
    this.serverAt,
    this.tables,
    this.excluded,
    this.format,
    this.version,
    this.archiveSha256,
    this.conflictManifest,
    this.conflictManifestSha256,
  );

  final String clinic, serverAt, format, archiveSha256, conflictManifestSha256;
  final int version;
  final Map<String, int> tables;
  final List<String> excluded;
  final Map<String, List<String>> conflictManifest;

  bool get clinicBackup => format == 'vetdosis-operational-backup';
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
    if (!{
          'vetdosis-operational-backup',
          'vetdosis-personal-backup',
        }.contains(snapshot['format']) ||
        snapshot['version'] != 1) {
      throw const FormatException('No es un respaldo operacional compatible.');
    }

    final source = snapshot['tables'];
    if (source is! Map) {
      throw const FormatException('El respaldo no contiene tablas válidas.');
    }

    final counts = <String, int>{};
    final manifest = <String, List<String>>{};
    const conflictTables = {
      'vet_owners',
      'vet_patients',
      'clinical_cases',
      'hospital_stays',
      'form_documents',
      'prescriptions',
      'medication_vials',
      'inventario',
      'lotes_inventario',
      'clinic_appointments',
      'clinic_tasks',
      'clinic_messages',
    };
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );

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
        if (row['id'] != null && !ids.add('${row['id']}')) {
          throw FormatException(
            'Hay identificadores repetidos en ${entry.key}.',
          );
        }
      }

      final name = entry.key as String;
      counts[name] = (entry.value as List).length;
      if (conflictTables.contains(name)) {
        final values = <String>{};
        for (final row in entry.value as List) {
          final id = (row as Map)['id'];
          if (id != null) {
            if (id is! String || !uuidPattern.hasMatch(id)) {
              throw FormatException('Identificador inválido en $name.');
            }
            values.add(id.toLowerCase());
          }
        }
        manifest[name] = values.toList()..sort();
      }
    }

    final canonicalManifest = jsonEncode({
      for (final key in (manifest.keys.toList()..sort())) key: manifest[key],
    });
    final scope = snapshot['scope'];
    final raw = scope is Map ? scope['excluded'] : null;

    return BackupRecoveryReport._(
      expectedClinic,
      '${snapshot['server_at'] ?? 'Fecha no registrada'}',
      counts,
      raw is List ? raw.map((v) => v.toString()).toList() : [],
      snapshot['format'] as String,
      snapshot['version'] as int,
      sha256.convert(archive).toString(),
      manifest,
      sha256.convert(utf8.encode(canonicalManifest)).toString(),
    );
  }

  String toJson() => const JsonEncoder.withIndent('  ').convert({
    'format': 'vetdosis-recovery-inspection',
    'version': 1,
    'clinic_id': clinic,
    'server_at': serverAt,
    'record_count': records,
    'archive_sha256': archiveSha256,
    'conflict_manifest_sha256': conflictManifestSha256,
    'conflict_manifest_tables': conflictManifest.map(
      (key, value) => MapEntry(key, value.length),
    ),
    'tables': tables,
    'excluded': excluded,
    'restored': false,
    'scope':
        'Inspección sin cambios en la base de datos; no acredita origen ni restaurabilidad completa.',
  });
}
