import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'backup_archive.dart';

typedef RestoreDependencyManifest =
    Map<String, Map<String, List<Map<String, String>>>>;

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
    this.dependencyManifest,
    this.dependencyManifestSha256,
    this.restoreOwners,
  );

  final String clinic, serverAt, format, archiveSha256, conflictManifestSha256;
  final String dependencyManifestSha256;
  final int version;
  final Map<String, int> tables;
  final List<String> excluded;
  final Map<String, List<String>> conflictManifest;
  final RestoreDependencyManifest dependencyManifest;
  final List<Map<String, dynamic>> restoreOwners;

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
    final dependencies = <String, Map<String, List<Map<String, String>>>>{};
    final ownersForRestore = <Map<String, dynamic>>[];
    const conflictTables = {
      'vet_owners',
      'vet_patients',
      'form_templates',
      'form_template_versions',
      'form_documents',
      'professional_profiles',
      'professional_delegations',
      'clinical_cases',
      'hospital_stays',
      'prescriptions',
      'medication_vials',
      'inventario',
      'lotes_inventario',
      'clinic_appointments',
      'clinic_tasks',
      'clinic_messages',
    };
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}
    );

    String requiredUuid(Object? value, String table, String field) {
      if (value is! String || !uuidPattern.hasMatch(value)) {
        throw FormatException('Identificador inválido en $table.$field.');
      }
      return value.toLowerCase();
    }

    void dependency(
      List<Map<String, String>> target,
      String table,
      Object? value,
      String sourceTable,
      String field, {
      bool optional = false,
    }) {
      if (value == null && optional) return;
      target.add({
        'table': table,
        'id': requiredUuid(value, sourceTable, field),
      });
    }

    for (final entry in source.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Una tabla del respaldo no es válida.');
      }
      final name = entry.key as String;
      final rows = entry.value as List;
      counts[name] = rows.length;
      final ids = <String>{};
      final tableDependencies = <String, List<Map<String, String>>>{};

      for (final raw in rows) {
        if (raw is! Map) {
          throw const FormatException('Una fila del respaldo no es válida.');
        }
        final row = Map<String, dynamic>.from(raw);
        if (row['clinic_id'] != null && row['clinic_id'] != expectedClinic) {
          throw const FormatException(
            'El archivo mezcla registros de distintas clínicas.',
          );
        }
        if (row['id'] != null && !ids.add('${row['id']}')) {
          throw FormatException('Hay identificadores repetidos en $name.');
        }
        if (name == 'vet_owners') {
          if (row['clinic_id'] != expectedClinic) {
            throw const FormatException(
              'Un tutor del respaldo no declara la clínica esperada.',
            );
          }
          final id = requiredUuid(row['id'], name, 'id');
          final ownerName = row['name'];
          if (ownerName is! String ||
              ownerName.trim().isEmpty ||
              ownerName.trim().length > 200) {
            throw const FormatException('Tutor inválido en el respaldo.');
          }
          String textField(String field) {
            final value = row[field];
            if (value == null) return '';
            if (value is! String || value.length > 1000) {
              throw FormatException('Campo inválido en vet_owners.$field.');
            }
            return value;
          }
          String? sourceCreatedBy;
          if (row['created_by'] != null) {
            sourceCreatedBy = requiredUuid(
              row['created_by'],
              name,
              'created_by',
            );
          }
          String? sourceCreatedAt;
          if (row['created_at'] != null) {
            final rawCreatedAt = row['created_at'];
            if (rawCreatedAt is! String ||
                DateTime.tryParse(rawCreatedAt) == null) {
              throw const FormatException(
                'Fecha de creación inválida en vet_owners.',
              );
            }
            sourceCreatedAt = rawCreatedAt;
          }
          ownersForRestore.add({
            'id': id,
            'clinic_id': expectedClinic,
            'name': ownerName.trim(),
            'phone': textField('phone'),
            'email': textField('email'),
            'address': textField('address'),
            'source_created_by': ?sourceCreatedBy,
            'source_created_at': ?sourceCreatedAt,
          });
        }
        if (!conflictTables.contains(name)) continue;

        final id = requiredUuid(row['id'], name, 'id');
        final rowDependencies = <Map<String, String>>[];
        switch (name) {
          case 'vet_patients':
            dependency(rowDependencies, 'vet_owners', row['owner_id'], name, 'owner_id');
            break;
          case 'form_templates':
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by', optional: true);
            break;
          case 'form_template_versions':
            dependency(rowDependencies, 'form_templates', row['template_id'], name, 'template_id');
            dependency(rowDependencies, 'form_template_versions', row['base_version_id'], name, 'base_version_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by', optional: true);
            break;
          case 'form_documents':
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id');
            dependency(rowDependencies, 'form_template_versions', row['version_id'], name, 'version_id');
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id');
            dependency(rowDependencies, 'clinic_members', row['assigned_aux_id'], name, 'assigned_aux_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            break;
          case 'professional_profiles':
            dependency(rowDependencies, 'clinic_members', row['user_id'], name, 'user_id');
            break;
          case 'professional_delegations':
            dependency(rowDependencies, 'professional_profiles', row['profile_id'], name, 'profile_id');
            dependency(rowDependencies, 'clinic_members', row['recipient_id'], name, 'recipient_id');
            dependency(rowDependencies, 'clinical_cases', row['case_id'], name, 'case_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            break;
          case 'clinical_cases':
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id');
            dependency(rowDependencies, 'form_documents', row['document_id'], name, 'document_id');
            dependency(rowDependencies, 'form_documents', row['consent_id'], name, 'consent_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id');
            break;
          case 'hospital_stays':
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id');
            dependency(rowDependencies, 'clinic_members', row['admitted_by'], name, 'admitted_by');
            dependency(rowDependencies, 'clinic_members', row['discharged_by'], name, 'discharged_by', optional: true);
            break;
          case 'prescriptions':
            dependency(rowDependencies, 'clinical_cases', row['case_id'], name, 'case_id');
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id');
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id');
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            dependency(rowDependencies, 'professional_profiles', row['profile_id'], name, 'profile_id', optional: true);
            dependency(rowDependencies, 'professional_delegations', row['delegation_id'], name, 'delegation_id', optional: true);
            break;
          case 'medication_vials':
            dependency(rowDependencies, 'inventario', row['inventory_id'], name, 'inventory_id', optional: true);
            dependency(rowDependencies, 'lotes_inventario', row['inventory_lot_id'], name, 'inventory_lot_id', optional: true);
            dependency(rowDependencies, 'medication_product_versions', row['product_version_id'], name, 'product_version_id');
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id');
            break;
          case 'inventario':
            dependency(rowDependencies, 'medication_product_versions', row['medication_version_id'], name, 'medication_version_id', optional: true);
            break;
          case 'lotes_inventario':
            dependency(rowDependencies, 'inventario', row['item_id'], name, 'item_id');
            break;
          case 'clinic_appointments':
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['professional_id'], name, 'professional_id');
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            break;
          case 'clinic_tasks':
            dependency(rowDependencies, 'clinic_members', row['assigned_to'], name, 'assigned_to', optional: true);
            dependency(rowDependencies, 'clinic_members', row['completed_by'], name, 'completed_by', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            break;
          case 'clinic_messages':
            dependency(rowDependencies, 'clinic_members', row['author_id'], name, 'author_id');
            break;
        }
        rowDependencies.sort((a, b) {
          final table = a['table']!.compareTo(b['table']!);
          return table != 0 ? table : a['id']!.compareTo(b['id']!);
        });
        tableDependencies[id] = rowDependencies;
      }

      if (conflictTables.contains(name)) {
        manifest[name] = tableDependencies.keys.toList()..sort();
        dependencies[name] = {
          for (final id in (tableDependencies.keys.toList()..sort()))
            id: tableDependencies[id]!,
        };
      }
    }

    final canonicalManifest = jsonEncode({
      for (final key in (manifest.keys.toList()..sort())) key: manifest[key],
    });
    final canonicalDependencies = jsonEncode({
      for (final table in (dependencies.keys.toList()..sort()))
        table: {
          for (final id in (dependencies[table]!.keys.toList()..sort()))
            id: dependencies[table]![id],
        },
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
      dependencies,
      sha256.convert(utf8.encode(canonicalDependencies)).toString(),
      ownersForRestore..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String)),
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
    'dependency_manifest_sha256': dependencyManifestSha256,
    'conflict_manifest_tables': conflictManifest.map(
      (key, value) => MapEntry(key, value.length),
    ),
    'tables': tables,
    'restore_owner_candidates': restoreOwners.length,
    'excluded': excluded,
    'restored': false,
    'scope':
        'Inspección sin cambios en la base de datos; no acredita origen ni restaurabilidad completa.',
  });
}
,
    );

    String requiredUuid(Object? value, String table, String field) {
      if (value is! String || !uuidPattern.hasMatch(value)) {
        throw FormatException('Identificador inválido en $table.$field.');
      }
      return value.toLowerCase();
    }

    void dependency(
      List<Map<String, String>> target,
      String table,
      Object? value,
      String sourceTable,
      String field, {
      bool optional = false,
    }) {
      if (value == null && optional) return;
      target.add({
        'table': table,
        'id': requiredUuid(value, sourceTable, field),
      });
    }

    for (final entry in source.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Una tabla del respaldo no es válida.');
      }
      final name = entry.key as String;
      final rows = entry.value as List;
      counts[name] = rows.length;
      final ids = <String>{};
      final tableDependencies = <String, List<Map<String, String>>>{};

      for (final raw in rows) {
        if (raw is! Map) {
          throw const FormatException('Una fila del respaldo no es válida.');
        }
        final row = Map<String, dynamic>.from(raw);
        if (row['clinic_id'] != null && row['clinic_id'] != expectedClinic) {
          throw const FormatException(
            'El archivo mezcla registros de distintas clínicas.',
          );
        }
        if (row['id'] != null && !ids.add('${row['id']}')) {
          throw FormatException('Hay identificadores repetidos en $name.');
        }
        if (name == 'vet_owners') {
          if (row['clinic_id'] != expectedClinic) {
            throw const FormatException(
              'Un tutor del respaldo no declara la clínica esperada.',
            );
          }
          final id = requiredUuid(row['id'], name, 'id');
          final ownerName = row['name'];
          if (ownerName is! String ||
              ownerName.trim().isEmpty ||
              ownerName.trim().length > 200) {
            throw const FormatException('Tutor inválido en el respaldo.');
          }
          String textField(String field) {
            final value = row[field];
            if (value == null) return '';
            if (value is! String || value.length > 1000) {
              throw FormatException('Campo inválido en vet_owners.$field.');
            }
            return value;
          }
          String? sourceCreatedBy;
          if (row['created_by'] != null) {
            sourceCreatedBy = requiredUuid(
              row['created_by'],
              name,
              'created_by',
            );
          }
          String? sourceCreatedAt;
          if (row['created_at'] != null) {
            final rawCreatedAt = row['created_at'];
            if (rawCreatedAt is! String ||
                DateTime.tryParse(rawCreatedAt) == null) {
              throw const FormatException(
                'Fecha de creación inválida en vet_owners.',
              );
            }
            sourceCreatedAt = rawCreatedAt;
          }
          ownersForRestore.add({
            'id': id,
            'clinic_id': expectedClinic,
            'name': ownerName.trim(),
            'phone': textField('phone'),
            'email': textField('email'),
            'address': textField('address'),
            'source_created_by': ?sourceCreatedBy,
            'source_created_at': ?sourceCreatedAt,
          });
        }
        if (!conflictTables.contains(name)) continue;

        final id = requiredUuid(row['id'], name, 'id');
        final rowDependencies = <Map<String, String>>[];
        switch (name) {
          case 'vet_patients':
            dependency(rowDependencies, 'vet_owners', row['owner_id'], name, 'owner_id');
            break;
          case 'form_templates':
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by', optional: true);
            break;
          case 'form_template_versions':
            dependency(rowDependencies, 'form_templates', row['template_id'], name, 'template_id');
            dependency(rowDependencies, 'form_template_versions', row['base_version_id'], name, 'base_version_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by', optional: true);
            break;
          case 'form_documents':
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id');
            dependency(rowDependencies, 'form_template_versions', row['version_id'], name, 'version_id');
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id');
            dependency(rowDependencies, 'clinic_members', row['assigned_aux_id'], name, 'assigned_aux_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            break;
          case 'professional_profiles':
            dependency(rowDependencies, 'clinic_members', row['user_id'], name, 'user_id');
            break;
          case 'professional_delegations':
            dependency(rowDependencies, 'professional_profiles', row['profile_id'], name, 'profile_id');
            dependency(rowDependencies, 'clinic_members', row['recipient_id'], name, 'recipient_id');
            dependency(rowDependencies, 'clinical_cases', row['case_id'], name, 'case_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            break;
          case 'clinical_cases':
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id');
            dependency(rowDependencies, 'form_documents', row['document_id'], name, 'document_id');
            dependency(rowDependencies, 'form_documents', row['consent_id'], name, 'consent_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id');
            break;
          case 'hospital_stays':
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id');
            dependency(rowDependencies, 'clinic_members', row['admitted_by'], name, 'admitted_by');
            dependency(rowDependencies, 'clinic_members', row['discharged_by'], name, 'discharged_by', optional: true);
            break;
          case 'prescriptions':
            dependency(rowDependencies, 'clinical_cases', row['case_id'], name, 'case_id');
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id');
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id');
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            dependency(rowDependencies, 'professional_profiles', row['profile_id'], name, 'profile_id', optional: true);
            dependency(rowDependencies, 'professional_delegations', row['delegation_id'], name, 'delegation_id', optional: true);
            break;
          case 'medication_vials':
            dependency(rowDependencies, 'inventario', row['inventory_id'], name, 'inventory_id', optional: true);
            dependency(rowDependencies, 'lotes_inventario', row['inventory_lot_id'], name, 'inventory_lot_id', optional: true);
            dependency(rowDependencies, 'medication_product_versions', row['product_version_id'], name, 'product_version_id');
            dependency(rowDependencies, 'clinic_members', row['responsible_id'], name, 'responsible_id');
            break;
          case 'inventario':
            dependency(rowDependencies, 'medication_product_versions', row['medication_version_id'], name, 'medication_version_id', optional: true);
            break;
          case 'lotes_inventario':
            dependency(rowDependencies, 'inventario', row['item_id'], name, 'item_id');
            break;
          case 'clinic_appointments':
            dependency(rowDependencies, 'vet_patients', row['patient_id'], name, 'patient_id', optional: true);
            dependency(rowDependencies, 'clinic_members', row['professional_id'], name, 'professional_id');
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            break;
          case 'clinic_tasks':
            dependency(rowDependencies, 'clinic_members', row['assigned_to'], name, 'assigned_to', optional: true);
            dependency(rowDependencies, 'clinic_members', row['completed_by'], name, 'completed_by', optional: true);
            dependency(rowDependencies, 'clinic_members', row['created_by'], name, 'created_by');
            break;
          case 'clinic_messages':
            dependency(rowDependencies, 'clinic_members', row['author_id'], name, 'author_id');
            break;
        }
        rowDependencies.sort((a, b) {
          final table = a['table']!.compareTo(b['table']!);
          return table != 0 ? table : a['id']!.compareTo(b['id']!);
        });
        tableDependencies[id] = rowDependencies;
      }

      if (conflictTables.contains(name)) {
        manifest[name] = tableDependencies.keys.toList()..sort();
        dependencies[name] = {
          for (final id in (tableDependencies.keys.toList()..sort()))
            id: tableDependencies[id]!,
        };
      }
    }

    final canonicalManifest = jsonEncode({
      for (final key in (manifest.keys.toList()..sort())) key: manifest[key],
    });
    final canonicalDependencies = jsonEncode({
      for (final table in (dependencies.keys.toList()..sort()))
        table: {
          for (final id in (dependencies[table]!.keys.toList()..sort()))
            id: dependencies[table]![id],
        },
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
      dependencies,
      sha256.convert(utf8.encode(canonicalDependencies)).toString(),
      ownersForRestore..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String)),
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
    'dependency_manifest_sha256': dependencyManifestSha256,
    'conflict_manifest_tables': conflictManifest.map(
      (key, value) => MapEntry(key, value.length),
    ),
    'tables': tables,
    'restore_owner_candidates': restoreOwners.length,
    'excluded': excluded,
    'restored': false,
    'scope':
        'Inspección sin cambios en la base de datos; no acredita origen ni restaurabilidad completa.',
  });
}
