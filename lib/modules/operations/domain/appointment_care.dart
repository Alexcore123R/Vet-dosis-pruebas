import '../../patients/domain/patient_models.dart';

abstract interface class AppointmentCareRepository {
  Future<Map<String, dynamic>> careSnapshot(String clinic, List<String> ids);
  Future<void> careWrite(
    String clinic,
    String appointment,
    int version,
    String action,
    Map<String, dynamic> data,
    String operation,
  );
}

Map<String, dynamic> validateCare(String action, Map<String, dynamic> raw) {
  final keys = switch (action) {
    'admit' => [
      'reason',
      'belongings',
      'authorized_services',
      'authorized_by',
      'pickup_person',
      'budget_reference',
    ],
    'ready' => ['instructions', 'treatment', 'followup', 'clinical_date'],
    'deliver' => ['released_to', 'pickup_authorization', 'belongings_outcome'],
    _ => throw const FormatException('Acción de atención no válida.'),
  };
  final required = switch (action) {
    'admit' => [
      'reason',
      'belongings',
      'authorized_services',
      'authorized_by',
      'pickup_person',
    ],
    'ready' => ['instructions'],
    _ => ['released_to', 'belongings_outcome'],
  };
  final result = <String, dynamic>{};
  for (final key in keys) {
    result[key] = textField(
      raw,
      key,
      required: required.contains(key),
      max: ['instructions', 'treatment', 'followup'].contains(key) ? 1200 : 500,
    );
  }
  if (action == 'admit') {
    if (raw['budget_accepted'] != null && raw['budget_accepted'] is! bool) {
      throw const FormatException('Revisa la aceptación del presupuesto.');
    }
    result['budget_accepted'] = raw['budget_accepted'] == true;
    if (result['budget_accepted'] == true && result['budget_reference'] == '') {
      throw const FormatException('Identifica el presupuesto aceptado.');
    }
  }
  if (action == 'ready' && result['clinical_date'] != '') {
    result['clinical_date'] = calendarDate(result['clinical_date'] as String);
  }
  if (action == 'deliver') {
    for (final key in ['pickup_verified', 'instructions_delivered']) {
      if (raw[key] != true) {
        throw const FormatException(
          'Confirma la autorización de recogida y la entrega de indicaciones.',
        );
      }
      result[key] = true;
    }
  }
  return result;
}

/// Clinic-day bounds come from the server, including daylight-saving changes.
bool inCareQueue(Map<String, dynamic> row, DateTime start, DateTime end) {
  final at = DateTime.tryParse('${row['starts_at']}');
  if (at == null || !at.isBefore(end)) return false;
  return switch (row['state']) {
    'en_atencion' || 'listo' => true,
    'agendado' || 'entregado' => !at.isBefore(start),
    _ => false,
  };
}
