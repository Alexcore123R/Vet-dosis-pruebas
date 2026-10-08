enum ClinicRole {
  admin('Administrador'),
  mvz('MVZ'),
  auxiliar('Auxiliar'),
  recepcion('Recepción'),
  estilista('Estilista');

  const ClinicRole(this.label);
  final String label;
  static ClinicRole parse(String value) => ClinicRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => throw const FormatException('Rol desconocido'),
  );
}

class ClinicMembership {
  const ClinicMembership({
    required this.clinicId,
    required this.clinicName,
    required this.userId,
    required this.role,
    this.workspaceKind = 'clinic',
  });
  final String clinicId;
  final String clinicName;
  final String userId;
  final ClinicRole role;
  final String workspaceKind;
  bool get isPersonal => workspaceKind == 'personal';
}
