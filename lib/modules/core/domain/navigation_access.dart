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
    'Inventario' || 'Escanear producto' => role != ClinicRole.estilista,
    'Estadísticas' ||
    'Respaldo' ||
    'Estadísticas y respaldo' => role == ClinicRole.admin,
    'Checado' => !member.isPersonal,
    _ => true,
  };
}
