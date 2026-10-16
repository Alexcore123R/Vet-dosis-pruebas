import '../../auth/domain/clinic_membership.dart';

/// Presentation filter only. Clinical and data authorization stays on the server.
bool navigationAllowed(String page, ClinicMembership? member) {
  if (member == null) return true;
  final role = member.role;
  return switch (page) {
    'Cálculo rápido' ||
    'Cálculos clínicos' => [ClinicRole.admin, ClinicRole.mvz].contains(role),
    'Hospitalización' || 'Receta' || 'Formatos' => [
      ClinicRole.admin,
      ClinicRole.mvz,
      ClinicRole.auxiliar,
    ].contains(role),
    'Inventario' || 'Caja' || 'Escanear producto' => true,
    'Estadísticas' ||
    'Respaldo' ||
    'Estadísticas y respaldo' => role == ClinicRole.admin,
    'Equipo y avisos' || 'Pendientes del equipo' => !member.isPersonal,
    'Checado' => !member.isPersonal,
    _ => true,
  };
}
