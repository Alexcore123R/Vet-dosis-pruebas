import '../../auth/domain/clinic_membership.dart';
import 'module_access.dart';

/// Presentation filter only. Clinical and data authorization stays on the server.
bool navigationAllowed(
  String page,
  ClinicMembership? member, [
  ModuleAccess? access,
]) {
  if (member == null) return true;
  if (access != null && !moduleNavigationAllowed(page, member, access)) {
    return false;
  }
  final role = member.role;
  return switch (page) {
    'Planeación financiera' => role == ClinicRole.admin,
    'Cálculos' ||
    'Cálculo rápido' ||
    'Cálculos clínicos' => [ClinicRole.admin, ClinicRole.mvz].contains(role),
    'Hospitalización' || 'Receta' when access == null => [
      ClinicRole.admin,
      ClinicRole.mvz,
      ClinicRole.auxiliar,
    ].contains(role),
    'Hospitalización' || 'Receta' => true,
    'Inventario' || 'Caja' || 'Escanear producto' || 'Formatos' => true,
    'Estadísticas' ||
    'Respaldo' ||
    'Estadísticas y respaldo' when access == null => role == ClinicRole.admin,
    'Estadísticas' || 'Respaldo' || 'Estadísticas y respaldo' => true,
    'Equipo y avisos' || 'Pendientes del equipo' => !member.isPersonal,
    'Checado' => !member.isPersonal,
    _ => true,
  };
}
