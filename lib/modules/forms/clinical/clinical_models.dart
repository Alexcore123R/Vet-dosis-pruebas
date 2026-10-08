import '../../patients/domain/patient_models.dart' show textField;
import '../../doses/domain/quantity.dart';

const clinicalTypes = {'clinical_history', 'surgical_sheet', 'surgical_risk'};
const observationUnits = {
  'weight': 'kg',
  'fc': 'lpm',
  'fr': 'rpm',
  'pulse': 'lpm',
  'temperature': '°C',
  'tllc': 's',
  'bp_systolic': 'mmHg',
  'bp_diastolic': 'mmHg',
};
const observationNames = {
  'weight': 'Peso',
  'fc': 'Frecuencia cardíaca',
  'fr': 'Frecuencia respiratoria',
  'pulse': 'Pulso',
  'temperature': 'Temperatura',
  'tllc': 'TLLC',
  'bp_systolic': 'Presión sistólica',
  'bp_diastolic': 'Presión diastólica',
};
const clinicalScopes = {
  'observaciones': 'Mediciones',
  'evaluacion': 'Evaluación',
  'cirugia': 'Cirugía',
  'anestesia': 'Anestesia',
  'recuperacion': 'Recuperación',
  'cuidados': 'Cuidados',
};

DateTime clinicalInstant(String text) {
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
  ).hasMatch(text)) {
    throw const FormatException('La hora debe ser UTC, con fecha y segundos.');
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null ||
      parsed.toIso8601String().substring(0, 19) != text.substring(0, 19)) {
    throw const FormatException('Fecha y hora inválidas.');
  }
  return parsed.toUtc();
}

String clinicalNumber(String text, String kind) {
  if (!observationUnits.containsKey(kind)) {
    throw const FormatException('Medición desconocida.');
  }
  final value = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^-?\d{1,12}(\.\d{1,9})?$').hasMatch(value)) {
    throw const FormatException(
      'Usa un decimal exacto, sin separadores de miles.',
    );
  }
  if (kind != 'temperature' && value.startsWith('-')) {
    throw const FormatException('La medición no admite un valor negativo.');
  }
  if (kind == 'weight' && !Quantity.parse(value).positive) {
    throw const FormatException('El peso debe ser mayor que cero.');
  }
  return value;
}

Map<String, dynamic> validateObservation(Map<String, dynamic> input) {
  final kind = textField(input, 'kind', required: true, max: 40);
  final value = clinicalNumber(
    textField(input, 'value', required: true, max: 40),
    kind,
  );
  final at = clinicalInstant(
    textField(input, 'observed_at', required: true, max: 40),
  );
  final unit = textField(input, 'unit', required: true, max: 20);
  if (unit != observationUnits[kind]) {
    throw const FormatException('La unidad no corresponde a la medición.');
  }
  return {
    'kind': kind,
    'value': value,
    'unit': unit,
    'observed_at': at.toIso8601String(),
    'performed_by': textField(input, 'performed_by', required: true, max: 36),
    'notes': textField(input, 'notes'),
    if (input['replaces_id'] != null)
      'replaces_id': textField(input, 'replaces_id', required: true, max: 36),
    if (input['replaces_id'] != null)
      'correction_reason': textField(
        input,
        'correction_reason',
        required: true,
        max: 1000,
      ),
  };
}

class ClinicalCase {
  ClinicalCase(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'];
  String get patientId => data['patient_id'];
  String get responsibleId => data['responsible_id'];
  String get documentId => data['document_id'];
  String get kind => data['kind'];
  String get title => data['title'];
  String get patientName => data['patient_name'];
  DateTime get createdAt => DateTime.parse(data['created_at']);
}

class ClinicalBundle {
  ClinicalBundle(
    this.caseData,
    this.staff,
    this.observations,
    this.acts,
    this.authorizations,
  );
  final ClinicalCase caseData;
  final List<Map<String, dynamic>> staff, observations, acts, authorizations;
  factory ClinicalBundle.read(Map<String, dynamic> raw) => ClinicalBundle(
    ClinicalCase(Map<String, dynamic>.from(raw['case'])),
    (raw['staff'] as List).map((r) => Map<String, dynamic>.from(r)).toList(),
    (raw['observations'] as List)
        .map((r) => Map<String, dynamic>.from(r))
        .toList(),
    (raw['acts'] as List).map((r) => Map<String, dynamic>.from(r)).toList(),
    (raw['authorizations'] as List)
        .map((r) => Map<String, dynamic>.from(r))
        .toList(),
  );
}
