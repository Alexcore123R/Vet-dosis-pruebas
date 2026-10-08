import '../clinical/clinical_models.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../auth/domain/clinic_membership.dart';

const formTypes = {
  'general': 'Consentimiento general',
  'surgery': 'Sedación, anestesia y cirugía',
  'euthanasia': 'Eutanasia',
  'early_discharge': 'Alta anticipada',
  'hospital': 'Ingreso hospitalario',
  'clinical_history': 'Historia clínica',
  'surgical_sheet': 'Hoja quirúrgica y anestésica',
  'surgical_risk': 'Valoración prequirúrgica / ASA / EKG',
};
const protectedFieldIds = {
  'patient',
  'owner',
  'mvz_name',
  'mvz_license',
  'signer_name',
  'signer_id',
  'privacy_url',
  'signature',
};
const fieldTypes = {
  'text',
  'date',
  'checkbox',
  'single',
  'multiple',
  'table',
  'number',
  'binding',
  'signature',
  'person',
  'consent',
  'instant',
};

class FormsAccess {
  const FormsAccess(this.role);
  final ClinicRole role;
  bool get clinical =>
      [ClinicRole.admin, ClinicRole.mvz, ClinicRole.auxiliar].contains(role);
  bool get editTemplates => [ClinicRole.admin, ClinicRole.mvz].contains(role);
  bool get finalize => role == ClinicRole.mvz;
}

Map<String, dynamic> validateTemplate(Map<String, dynamic> input) {
  final schema = jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
  if (!formTypes.containsKey(schema['type']) ||
      schema['title'] is! String ||
      (schema['title'] as String).trim().isEmpty ||
      (schema['title'] as String).length > 200) {
    throw const FormatException('Revisa el tipo y título de la plantilla.');
  }
  final fields = schema['fields'];
  final clauses = schema['clauses'];
  if (fields is! List ||
      fields.length > 80 ||
      clauses is! List ||
      clauses.length > 40 ||
      jsonEncode(schema).length > 60000) {
    throw const FormatException('Estructura de plantilla inválida.');
  }
  final ids = <String>{};
  for (final field in fields) {
    if (field is! Map ||
        field['id'] is! String ||
        !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(field['id'] as String) ||
        !ids.add(field['id'] as String) ||
        !fieldTypes.contains(field['type']) ||
        field['label'] is! String ||
        (field['label'] as String).trim().isEmpty ||
        (field['label'] as String).length > 200 ||
        field['required'] is! bool ||
        field['locked'] is! bool) {
      throw const FormatException('Revisa los campos y sus claves.');
    }
    if (['single', 'multiple'].contains(field['type'])) {
      final options = field['options'];
      if (options is! List ||
          options.isEmpty ||
          options.length > 40 ||
          options.any(
            (o) => o is! String || o.trim().isEmpty || o.length > 200,
          ) ||
          options.toSet().length != options.length) {
        throw const FormatException('Opciones de selección inválidas.');
      }
    }
    if (field['type'] == 'table') {
      final columns = field['columns'];
      if (columns is! List ||
          columns.isEmpty ||
          columns.length > 12 ||
          columns.any(
            (c) => c is! String || c.trim().isEmpty || c.length > 100,
          ) ||
          columns.toSet().length != columns.length) {
        throw const FormatException('Columnas de tabla inválidas.');
      }
    }
  }
  final mandatory = clinicalTypes.contains(schema['type'])
      ? protectedFieldIds.difference({'signer_name', 'signer_id'})
      : protectedFieldIds;
  if (!ids.containsAll(mandatory)) {
    throw const FormatException('Faltan campos protegidos.');
  }
  for (final field in fields.cast<Map>()) {
    if (protectedFieldIds.contains(field['id']) &&
        (field['locked'] != true || field['required'] != true)) {
      throw const FormatException('Los campos protegidos son obligatorios.');
    }
  }
  final seen = <String>{};
  for (final clause in clauses) {
    if (clause is! Map ||
        clause['id'] is! String ||
        !seen.add(clause['id'] as String) ||
        clause['text'] is! String ||
        (clause['text'] as String).trim().isEmpty ||
        (clause['text'] as String).length > 12000 ||
        clause['locked'] is! bool) {
      throw const FormatException('Cláusulas inválidas.');
    }
    if (RegExp(
      r'\birrevocable\b',
      caseSensitive: false,
    ).hasMatch(clause['text'] as String)) {
      throw const FormatException(
        'El consentimiento debe permitir revocación.',
      );
    }
  }
  if (!clinicalTypes.contains(schema['type']) &&
      !clauses.any((c) => c['id'] == 'revocation' && c['locked'] == true)) {
    throw const FormatException('Falta la cláusula protegida de revocación.');
  }
  if (schema['type'] == 'euthanasia' &&
      !ids.containsAll({
        'clinical_reason',
        'prior_opinion',
        'method',
        'body_disposition',
        'cost',
      })) {
    throw const FormatException('Faltan campos específicos de eutanasia.');
  }
  return schema;
}

void validateValues(
  Map<String, dynamic> schema,
  Map<String, dynamic> values, {
  bool complete = false,
}) {
  final fields = (schema['fields'] as List).cast<Map>();
  final byId = {for (final f in fields) f['id'] as String: f};
  for (final entry in values.entries) {
    final field = byId[entry.key];
    if (field == null || ['binding', 'signature'].contains(field['type'])) {
      throw const FormatException('Campo no editable.');
    }
    final value = entry.value;
    final type = field['type'];
    if (type == 'checkbox') {
      if (value is! bool) throw const FormatException('Casilla inválida.');
    } else if (type == 'multiple') {
      if (value is! List ||
          value.toSet().length != value.length ||
          value.any((v) => !(field['options'] as List).contains(v))) {
        throw const FormatException('Selección inválida.');
      }
    } else if (type == 'table') {
      final columns = field['columns'] as List;
      if (value is! List ||
          value.length > 100 ||
          value.any(
            (row) =>
                row is! List ||
                row.length != columns.length ||
                row.any((cell) => cell is! String || cell.length > 1000),
          )) {
        throw const FormatException('Tabla inválida.');
      }
    } else {
      if (value is! String || value.length > 12000) {
        throw const FormatException('Texto inválido.');
      }
      if (type == 'single' &&
          value.isNotEmpty &&
          !(field['options'] as List).contains(value)) {
        throw const FormatException('Selección inválida.');
      }
      if (type == 'number' &&
          value.isNotEmpty &&
          !RegExp(r'^-?\d{1,12}(\.\d{1,9})?$').hasMatch(value)) {
        throw const FormatException('Número inválido.');
      }
      if (type == 'instant' && value.isNotEmpty) clinicalInstant(value);
      if (['person', 'consent'].contains(type) &&
          value.isNotEmpty &&
          !RegExp(
            r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
          ).hasMatch(value)) {
        throw const FormatException('Identificador inválido.');
      }
      if (type == 'date' && value.isNotEmpty) {
        final parsed = DateTime.tryParse(value);
        if (parsed == null ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
            parsed.toIso8601String().substring(0, 10) != value) {
          throw const FormatException('Fecha inválida.');
        }
      }
      if (entry.key == 'privacy_url' && value.isNotEmpty) {
        final uri = Uri.tryParse(value);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
          throw const FormatException(
            'El aviso de privacidad requiere un enlace HTTPS.',
          );
        }
      }
    }
  }
  if (complete) {
    for (final field in fields.where(
      (f) =>
          f['required'] == true &&
          !['binding', 'signature'].contains(f['type']),
    )) {
      final value = values[field['id']];
      if (value == null ||
          value == false ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty)) {
        throw FormatException('Completa ${field['label']}.');
      }
    }
  }
}

class FormTemplateVersion {
  const FormTemplateVersion(
    this.id,
    this.templateId,
    this.version,
    this.schema,
    this.clinicId,
    this.responsibleId,
    this.baseVersionId,
    this.approved, {
    this.reason = '',
    this.createdBy,
    this.createdAt,
  });
  final String id, templateId;
  final String? clinicId, responsibleId, baseVersionId;
  final int version;
  final bool approved;
  final String reason;
  final String? createdBy, createdAt;
  final Map<String, dynamic> schema;
  factory FormTemplateVersion.read(Map<String, dynamic> row) =>
      FormTemplateVersion(
        row['id'] as String,
        row['template_id'] as String,
        row['version'] as int,
        Map<String, dynamic>.from(row['schema']),
        row['clinic_id'] as String?,
        row['responsible_id'] as String?,
        row['base_version_id'] as String?,
        row['approved'] == true,
        reason: row['reason'] as String? ?? '',
        createdBy: row['created_by'] as String?,
        createdAt: row['created_at'] as String?,
      );
}

class FormDocument {
  const FormDocument(
    this.id,
    this.state,
    this.revision,
    this.versionId,
    this.responsibleId,
    this.values,
    this.snapshot,
    this.pdfHash, {
    this.branding = const {},
  });
  final String id, state, versionId, responsibleId;
  final int revision;
  final Map<String, dynamic> values, snapshot, branding;
  final String? pdfHash;
  bool get signed => state == 'signed';
  bool get clinical => clinicalTypes.contains(snapshot['schema']['type']);
  factory FormDocument.read(Map<String, dynamic> row) => FormDocument(
    row['id'] as String,
    row['state'] as String,
    row['revision'] as int,
    row['version_id'] as String,
    row['responsible_id'] as String,
    Map<String, dynamic>.from(row['values']),
    Map<String, dynamic>.from(row['snapshot']),
    row['pdf_hash'] as String?,
    branding: Map<String, dynamic>.from(row['branding'] ?? {}),
  );
}

class ReviewedPdf {
  ReviewedPdf(this.bytes, this.hash) {
    if (bytes.length < 5 ||
        utf8.decode(bytes.sublist(0, 5)) != '%PDF-' ||
        sha256.convert(bytes).toString() != hash) {
      throw const FormatException(
        'El PDF no coincide con su hash de servidor.',
      );
    }
  }
  final Uint8List bytes;
  final String hash;
}

String formStateLabel(String state) => switch (state) {
  'draft' => 'Borrador',
  'awaiting_review' => 'Pendiente de generar PDF',
  'ready' => 'Listo para revisión y aceptación',
  'signed' => 'Firmado',
  _ => 'Estado desconocido',
};
