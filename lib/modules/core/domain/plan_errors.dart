/// Converts known limits to actionable messages without exposing server details.
String? planActionError(Object error) {
  final text = error.toString();
  if (text.contains('patient_plan_limit')) {
    return 'Alcanzaste el límite de pacientes de tu plan. Consulta Planes; tus registros existentes se conservan.';
  }
  if (text.contains('storage_plan_limit')) {
    return 'Alcanzaste el presupuesto de almacenamiento de tu plan. Consulta Planes para revisar el uso y las opciones.';
  }
  if (text.contains('clinic_plan_required')) {
    return 'Esta función compartida requiere un plan de clínica vigente. Consulta Planes; pagar no cambia tu rol.';
  }
  return null;
}
