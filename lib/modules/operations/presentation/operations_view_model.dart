import '../../core/domain/plan_errors.dart';
import 'package:flutter/foundation.dart';
import '../domain/operations_repository.dart';
import '../domain/appointment_links.dart';
import '../domain/appointment_care.dart';

class OperationsViewModel extends ChangeNotifier {
  OperationsViewModel(this.repository, this.clinic);
  final OperationsRepository repository;
  final String clinic;
  Map<String, dynamic> data = {};
  Map<String, Map<String, dynamic>> links = {};
  String? linksError;
  Map<String, Map<String, dynamic>> care = {};
  Map<String, dynamic>? careWindow;
  String? careError;
  int _generation = 0;
  void suspend() {
    if (_disposed) return;
    _generation++;
    data = {};
    links = {};
    care = {};
    careWindow = null;
    busy = false;
    notifyListeners();
  }

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
  String? sectionReason(String section) => data['section_reasons'] is Map
      ? (data['section_reasons'] as Map)[section] as String?
      : null;
  List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Future<void> load() async {
    if (_disposed || busy) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    care = {};
    careWindow = null;
    careError = null;
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
      if (_disposed || generation != _generation) return;
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
          if (_disposed || generation != _generation) return;
          links = nextLinks;
        } catch (_) {
          if (_disposed || generation != _generation) return;
          links = {};
          linksError =
              'No se pudieron comprobar contactos y pagos; actualiza antes de utilizarlos.';
        }
      }
      if (repository is AppointmentCareRepository &&
          (next['permissions'] is! Map ||
              (next['permissions'] as Map)['appointment.read'] == true)) {
        try {
          final snapshot = await (repository as AppointmentCareRepository)
              .careSnapshot(
                clinic,
                rows('appointments').map((a) => a['id'] as String).toList(),
              );
          if (_disposed || generation != _generation) return;
          if (snapshot['schema_version'] != 1 ||
              snapshot['clinic_id'] != clinic ||
              snapshot['appointments'] is! List ||
              DateTime.tryParse('${snapshot['day_start']}') == null ||
              DateTime.tryParse('${snapshot['day_end']}') == null) {
            throw const FormatException('Contrato de atención no compatible.');
          }
          final ids = rows('appointments').map((a) => a['id']).toSet();
          final checked = <String, Map<String, dynamic>>{};
          for (final raw in snapshot['appointments'] as List) {
            final row = Map<String, dynamic>.from(raw as Map);
            if (!ids.contains(row['appointment_id']) ||
                row['records'] is! List ||
                row['can_manage'] is! bool ||
                row['can_close'] is! bool) {
              throw const FormatException(
                'Registro de atención no compatible.',
              );
            }
            checked[row['appointment_id'] as String] = row;
          }
          careWindow = snapshot;
          care = checked;
        } catch (_) {
          if (_disposed || generation != _generation) return;
          care = {};
          careWindow = null;
          careError =
              'No se pudo comprobar el ingreso y la entrega. Actualiza antes de utilizarlos.';
        }
      }
    } catch (e) {
      if (_disposed || generation != _generation) return;
      links = {};
      care = {};
      careWindow = null;
      data = {};
      error = operationError(e);
    }
    if (_disposed || generation != _generation) return;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    care = {};
    careWindow = null;
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
    'supplier_archive_blocked':
        'No se puede archivar un proveedor con adeudo pendiente. Actualiza el saldo primero.',
    'supplier_fields_invalid':
        'Revisa nombre, contacto, tipo de proveedor y adeudo.',
    'supplier_not_found': 'El proveedor ya no está activo. Actualiza la lista.',
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
    'care_required': 'Completa los datos del ingreso o las indicaciones.',
    'care_budget_reference_required':
        'Identifica el presupuesto cuya aceptación se confirmó.',
    'care_date_required':
        'Usa una fecha clínica válida que no sea futura en la clínica.',
    'care_delivery_confirmation_required':
        'Confirma la recogida autorizada, las indicaciones y las pertenencias.',
    'clinical_data_not_allowed':
        'El tratamiento clínico se registra desde una consulta con permisos veterinarios.',
    'care_already_recorded':
        'Este paso ya quedó registrado. Actualiza la tarjeta.',
    'care_close_required':
        'Registra las indicaciones de cierre antes de entregar.',
    'care_patient_required':
        'Vincula la consulta con su expediente antes del cierre clínico.',
    'care_pickup_authorization_required':
        'Indica cómo se comprobó la autorización de quien recoge.',
    'clinical_role_required':
        'El cierre clínico requiere un veterinario autorizado.',
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
