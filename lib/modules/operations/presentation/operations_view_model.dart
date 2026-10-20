import '../../core/domain/plan_errors.dart';
import 'package:flutter/foundation.dart';
import '../domain/operations_repository.dart';
import '../domain/appointment_links.dart';

class OperationsViewModel extends ChangeNotifier {
  OperationsViewModel(this.repository, this.clinic);
  final OperationsRepository repository;
  final String clinic;
  Map<String, dynamic> data = {};
  Map<String, Map<String, dynamic>> links = {};
  String? linksError;
  bool busy = false, _disposed = false;
  String? error;
  bool explicitPermissions = false;
  bool allowed(String code) =>
      !busy &&
      error == null &&
      data['permissions'] is Map &&
      (data['permissions'] as Map)[code] == true;
  bool sectionAllowed(String section) =>
      data['sections'] is Map && (data['sections'] as Map)[section] == true;
  List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Future<void> load() async {
    if (_disposed || busy) return;
    busy = true;
    error = null;
    links = {};
    linksError = null;
    data = {};
    notifyListeners();
    try {
      final next = await repository.dashboard(clinic);
      if (explicitPermissions && next['permissions'] is! Map) {
        throw StateError('permission_snapshot_missing');
      }
      if (next['permissions'] is Map) explicitPermissions = true;
      if (_disposed) return;
      data = next;
      if (repository is AppointmentLinksRepository &&
          (next['permissions'] is! Map ||
              (next['permissions'] as Map)['appointment.read'] == true)) {
        try {
          final ids = <String>{
            for (final a in rows('appointments')) a['id'] as String,
            for (final act in rows('acts'))
              if (act['appointment_id'] is String)
                act['appointment_id'] as String,
          };
          final nextLinks = await (repository as AppointmentLinksRepository)
              .patientLinks(clinic, ids.toList());
          if (_disposed) return;
          links = nextLinks;
        } catch (_) {
          if (_disposed) return;
          links = {};
          linksError =
              'No se pudieron comprobar contactos y pagos; actualiza antes de utilizarlos.';
        }
      }
    } catch (e) {
      if (_disposed) return;
      links = {};
      data = {};
      error = operationError(e);
    }
    if (_disposed) return;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    data = {};
    links = {};
    super.dispose();
  }
}

String operationError(Object e) {
  final planMessage = planActionError(e);
  if (planMessage != null) return planMessage;
  final text = e.toString();
  const errors = {
    'explicit_permission_required':
        'Necesitas un permiso vigente para esta acción. Solicítalo a administración.',
    'clinic_appointments_check':
        'Revisa el horario: el fin debe ser posterior al inicio y la cita no puede durar más de 24 horas.',
    'invalid_display_name': 'Usa un nombre de entre 2 y 120 caracteres.',
    'patient_wrong_clinic':
        'El paciente no pertenece a esta clínica. Vuelve a seleccionarlo.',
    'appointment_reason_required':
        'Escribe un motivo de al menos 3 caracteres.',
    'appointment_not_scheduled': 'Solo se puede reprogramar una cita agendada.',
    'invalid_professional':
        'El profesional ya no está disponible en esta clínica.',
    'appointment_overlap': 'Ese profesional ya tiene una cita en ese horario.',
    'version_conflict': 'El registro cambió. Actualiza antes de guardar.',
    'consent_required': 'Confirma tu consentimiento para guardar la ficha.',
    'service_already_paid': 'Este servicio ya está cobrado.',
    'invalid_transition': 'Ese cambio de estado no está permitido.',
    'appointment_closed': 'La cita ya está cerrada.',
    'access_denied': 'No tienes permiso para esta acción.',
  };
  for (final entry in errors.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'No se pudo guardar o consultar. Revisa los datos, la conexión y tus permisos.';
}

void validateAppointmentTimes(Map<String, dynamic> data) {
  final start = DateTime.tryParse('${data['starts_at'] ?? ''}');
  final end = DateTime.tryParse('${data['ends_at'] ?? ''}');
  if (start == null || end == null) {
    throw const FormatException(
      'Selecciona las fechas y horas de inicio y fin.',
    );
  }
  if (!end.isAfter(start)) {
    throw const FormatException(
      'La fecha y hora de fin deben ser posteriores al inicio.',
    );
  }
  if (end.difference(start) > const Duration(hours: 24)) {
    throw const FormatException('La cita no puede durar más de 24 horas.');
  }
}
