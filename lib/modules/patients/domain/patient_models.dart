import '../../auth/domain/clinic_membership.dart';
import 'clinical_record_fields.dart';
import 'preventive_coverage.dart';
import '../../doses/domain/quantity.dart';

class PatientAccess {
  const PatientAccess(this.role);
  final ClinicRole role;
  bool get owners =>
      [ClinicRole.admin, ClinicRole.mvz, ClinicRole.recepcion].contains(role);
  bool get clinical =>
      [ClinicRole.admin, ClinicRole.mvz, ClinicRole.auxiliar].contains(role);
  bool get medical => [ClinicRole.admin, ClinicRole.mvz].contains(role);
  bool get createPatient => owners;
  bool canAdd(EventKind kind) =>
      kind == EventKind.soap || kind == EventKind.consent ? medical : clinical;
}

String textField(
  Map<String, dynamic> data,
  String key, {
  bool required = false,
  int max = 4000,
}) {
  final value = data[key];
  if (value != null && value is! String) {
    throw FormatException('$key inválido.');
  }
  final text = (value as String? ?? '').trim();
  if ((required && text.isEmpty) || text.length > max) {
    throw FormatException('Revisa $key.');
  }
  return text;
}

String calendarDate(String input) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
    throw const FormatException('Usa fecha AAAA-MM-DD.');
  }
  final date = DateTime.tryParse(input);
  if (date == null ||
      date.year < 1 ||
      date.toIso8601String().substring(0, 10) != input) {
    throw const FormatException('Fecha inválida.');
  }
  return input;
}

class VetPatient {
  const VetPatient({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.species,
    required this.breed,
    required this.sex,
    this.ownerId,
    this.birthDate,
  });
  final String id, clinicId, name, species, breed, sex;
  final String? ownerId, birthDate;
  factory VetPatient.read(Map<String, dynamic> row) => VetPatient(
    id: row['id'] as String,
    clinicId: row['clinic_id'] as String,
    name: row['name'] as String,
    species: row['species'] as String,
    breed: row['breed'] as String? ?? '',
    sex: row['sex'] as String? ?? 'sin especificar',
    ownerId: row['owner_id'] as String?,
    birthDate: row['birth_date'] as String?,
  );
}

class VetOwner {
  const VetOwner(this.id, this.name, this.phone, this.email, this.address);
  final String id, name, phone, email, address;
  factory VetOwner.read(Map<String, dynamic> row) => VetOwner(
    row['id'] as String,
    row['name'] as String,
    row['phone'] as String? ?? '',
    row['email'] as String? ?? '',
    row['address'] as String? ?? '',
  );
}

enum EventKind {
  soap('Consulta SOAP'),
  weight('Peso'),
  allergy('Alergia'),
  preventive('Vacuna / desparasitación'),
  consent('Consentimiento');

  const EventKind(this.label);
  final String label;
}

class PatientEvent {
  PatientEvent({
    required this.id,
    required this.kind,
    required Map<String, dynamic> data,
    required this.createdAt,
    required this.createdBy,
    this.formDocumentId,
    this.clinicalCaseId,
  }) : data = Map.unmodifiable(data);
  final String id, createdBy;
  final String? formDocumentId, clinicalCaseId;
  final EventKind kind;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  factory PatientEvent.read(Map<String, dynamic> row) => PatientEvent(
    id: row['id'] as String,
    kind: EventKind.values.byName(row['kind'] as String),
    data: Map<String, dynamic>.from(row['payload'] as Map),
    createdAt: DateTime.parse(row['created_at'] as String),
    createdBy: row['created_by'] as String,
    formDocumentId: row['form_document_id'] as String?,
    clinicalCaseId: row['clinical_case_id'] as String?,
  );
}

Map<String, dynamic> validateEvent(EventKind kind, Map<String, dynamic> raw) {
  final date = calendarDate(textField(raw, 'date', required: true));
  final out = <String, dynamic>{'date': date};
  switch (kind) {
    case EventKind.soap:
      out['reason'] = textField(raw, 'reason', required: true, max: 300);
      for (final key in ['subjective', 'objective', 'assessment', 'plan']) {
        out[key] = textField(raw, key);
      }
      if ([
        'subjective',
        'objective',
        'assessment',
        'plan',
      ].every((k) => (out[k] as String).isEmpty)) {
        throw const FormatException('Captura al menos un apartado SOAP.');
      }
      out['species_template'] = textField(
        raw,
        'species_template',
        required: true,
        max: 120,
      );
      if (raw['record_type'] == 'clinical_history') {
        out['record_type'] = 'clinical_history';
        for (final key in historyFields.keys) {
          out[key] = textField(raw, key);
        }
      }
    case EventKind.weight:
      final number = textField(raw, 'kg', required: true).replaceAll(',', '.');
      if (!Quantity.parse(number).positive) {
        throw const FormatException('El peso debe ser mayor que cero.');
      }
      out['kg'] = number;
    case EventKind.allergy:
      out['substance'] = textField(raw, 'substance', required: true, max: 300);
      out['reaction'] = textField(raw, 'reaction', required: true);
      out['notes'] = textField(raw, 'notes');
    case EventKind.preventive:
      final type = textField(raw, 'type', required: true);
      if (!['vacuna', 'desparasitación'].contains(type)) {
        throw const FormatException('Tipo preventivo inválido.');
      }
      out['type'] = type;
      if (raw.containsKey('preventive_version') &&
          raw['preventive_version'] != 1) {
        throw const FormatException('Versión del carnet no compatible.');
      }
      final extended = raw['preventive_version'] == 1;
      out['product'] = textField(raw, 'product', required: !extended, max: 300);
      if (extended) {
        final origin = textField(raw, 'origin', required: true);
        if (!preventiveOrigins.containsKey(origin)) {
          throw const FormatException('Selecciona el origen del antecedente.');
        }
        final precision = textField(raw, 'date_precision', required: true);
        if (!['exact', 'approximate', 'unknown'].contains(precision) ||
            (origin == 'clinic' && precision != 'exact')) {
          throw const FormatException('Revisa la fecha de aplicación.');
        }
        out['preventive_version'] = 1;
        out['origin'] = origin;
        out['date_precision'] = precision;
        for (final key in [
          'coverage',
          'date_description',
          'performer',
          'informant',
          'evidence_reference',
          'next_date_by',
        ]) {
          out[key] = textField(raw, key, max: 1000);
        }
        if (precision == 'approximate' && out['date_description'] == '') {
          throw const FormatException('Describe la fecha aproximada conocida.');
        }
        if (origin == 'external_document' && out['evidence_reference'] == '') {
          throw const FormatException(
            'Identifica el carnet o comprobante revisado.',
          );
        }
        if (origin == 'owner_report' && out['informant'] == '') {
          throw const FormatException('Indica quién refirió el antecedente.');
        }
        if (origin == 'clinic' && out['performer'] == '') {
          throw const FormatException('Indica quién realizó la aplicación.');
        }
        if (raw['coverage_version'] != 1 &&
            out['product'] == '' &&
            out['coverage'] == '') {
          throw const FormatException(
            'Captura producto, cobertura o tipo de desparasitación.',
          );
        }
      }
      if (raw['coverage_version'] != null) {
        if (raw['coverage_version'] != 1 || !extended) {
          throw const FormatException('Versión de cobertura no compatible.');
        }
        out['coverage_version'] = 1;
        out['coverage_components'] = validateCoverage(
          raw['coverage_components'],
        );
        out['coverage_other'] = textField(raw, 'coverage_other', max: 500);
        out['coverage'] = coverageText(
          (out['coverage_components'] as List).cast<String>(),
          out['coverage_other'] as String,
        );
        if (out['coverage'] == '' && out['product'] == '') {
          throw const FormatException(
            'Indica la cobertura conocida o el producto.',
          );
        }
      }
      out['batch'] = textField(raw, 'batch', max: 120);
      final due = textField(raw, 'next_date');
      out['next_date'] = due.isEmpty ? null : calendarDate(due);
      if (due.isNotEmpty && due.compareTo(date) < 0) {
        throw const FormatException(
          'La próxima fecha no puede ser anterior a la aplicación.',
        );
      }
      if (extended && due.isNotEmpty && out['next_date_by'] == '') {
        throw const FormatException(
          'Indica el profesional que señaló la próxima fecha.',
        );
      }
      if (extended && out['product'] == '') out['product'] = 'No especificado';
      out['notes'] = textField(raw, 'notes');
    case EventKind.consent:
      out['procedure'] = textField(raw, 'procedure', required: true, max: 300);
      out['text'] = textField(raw, 'text', required: true, max: 20000);
      out['signer'] = textField(raw, 'signer', required: true, max: 300);
      if (raw['accepted'] != true) {
        throw const FormatException(
          'Falta aceptar el texto de consentimiento.',
        );
      }
      final signature = raw['signature'];
      if (signature is! List ||
          signature.length < 2 ||
          signature.length > 5000) {
        throw const FormatException('Falta la firma en pantalla.');
      }
      int points = 0;
      double? firstX, firstY;
      bool moved = false;
      for (final point in signature) {
        if (point == null) continue;
        if (point is! List ||
            point.length != 2 ||
            point.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
          throw const FormatException('Firma inválida.');
        }
        final x = (point[0] as num).toDouble(),
            y = (point[1] as num).toDouble();
        firstX ??= x;
        firstY ??= y;
        if ((x - firstX).abs() + (y - firstY).abs() > 0.005) moved = true;
        points++;
      }
      if (points < 2 || !moved) {
        throw const FormatException('Dibuja la firma, no solo un punto.');
      }
      out['accepted'] = true;
      out['signature'] = signature
          .map(
            (p) => p == null
                ? null
                : List<num>.unmodifiable((p as List).cast<num>()),
          )
          .toList(growable: false);
  }
  return out;
}

class SoapTemplate {
  static Map<String, String> prompts(String species) => {
    'subjective': 'Motivo, evolución y antecedentes referidos por el tutor.',
    'objective': 'Hallazgos observados y mediciones; anota sus unidades.',
    'assessment':
        'Valoración del MVZ para $species; distingue sospechas y diagnósticos.',
    'plan': 'Plan indicado por el MVZ, seguimiento y revisión.',
  };
}
