// Structural capture fields only; no diagnostic defaults or vaccination schedule.
const historyFields = <String, String>{
  'medical_history': 'Enfermedades previas y crónicas',
  'surgical_history': 'Cirugías y procedimientos anteriores',
  'current_treatments': 'Tratamientos actuales',
  'family_history': 'Antecedentes familiares',
  'feeding': 'Alimentación',
  'environment': 'Procedencia, hábitat y hábitos',
  'reproductive_history': 'Antecedentes reproductivos',
  'anamnesis': 'Anamnesis y evolución',
  'physical_exam': 'Exploración física por sistemas',
  'vital_signs': 'Constantes fisiológicas (indica unidades)',
  'problem_list': 'Lista de problemas y diferenciales',
  'diagnostic_studies': 'Estudios e interpretación',
  'follow_up': 'Seguimiento indicado',
};

const preventiveOrigins = <String, String>{
  'clinic': 'Aplicada en esta clínica',
  'external_document': 'Documentada en carnet externo',
  'owner_report': 'Referida por el propietario',
};

String preventiveOriginLabel(Map<String, dynamic> data) =>
    preventiveOrigins[data['origin']] ?? 'Origen no especificado';

String preventiveDateLabel(Map<String, dynamic> data) {
  if (data['preventive_version'] == 1) {
    return switch (data['date_precision']) {
      'unknown' => 'Fecha de aplicación desconocida',
      'approximate' => 'Fecha aproximada: ${data['date_description']}',
      _ => 'Aplicación: ${data['date']}',
    };
  }
  return 'Fecha registrada: ${data['date']}';
}
