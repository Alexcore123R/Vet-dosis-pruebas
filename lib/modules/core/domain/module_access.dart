import '../../auth/domain/clinic_membership.dart';

abstract interface class ModuleAccessRepository {
  Future<Map<String, dynamic>> workspace(String clinicId);
}

class ModuleAccess {
  const ModuleAccess._(this.modules, this.summaries);

  final Map<String, bool> modules;
  final Map<String, bool> summaries;

  static const denied = ModuleAccess._(
    {
      'patients': false,
      'agenda': false,
      'hospital': false,
      'inventory': false,
      'sales': false,
      'prescriptions': false,
      'forms': false,
      'clinical': false,
      'statistics': false,
      'backup': false,
    },
    {
      'patients': false,
      'agenda': false,
      'hospital': false,
      'inventory': false,
      'sales': false,
    },
  );

  factory ModuleAccess.read(Map<String, dynamic> value) {
    if (value['schema_version'] != 1 ||
        value['mode'] != 'explicit_modules' ||
        value['modules'] is! Map ||
        value['summaries'] is! Map) {
      throw const FormatException('Contrato de módulos desconocido.');
    }
    final raw = Map<String, dynamic>.from(value['modules'] as Map);
    final rawSummaries = Map<String, dynamic>.from(value['summaries'] as Map);
    const expected = {
      'patients',
      'agenda',
      'hospital',
      'inventory',
      'sales',
      'prescriptions',
      'forms',
      'clinical',
      'statistics',
      'backup',
    };
    const expectedSummaries = {
      'patients',
      'agenda',
      'hospital',
      'inventory',
      'sales',
    };
    if (raw.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(raw.keys.toSet()).isNotEmpty ||
        raw.values.any((value) => value is! bool) ||
        rawSummaries.keys.toSet().difference(expectedSummaries).isNotEmpty ||
        expectedSummaries.difference(rawSummaries.keys.toSet()).isNotEmpty ||
        rawSummaries.values.any((value) => value is! bool)) {
      throw const FormatException('Capacidades de módulos inválidas.');
    }
    return ModuleAccess._(
      raw.cast<String, bool>(),
      rawSummaries.cast<String, bool>(),
    );
  }

  bool module(String name) => modules[name] == true;
  bool summary(String name) => summaries[name] == true;
}

/// Presentation only. Every data operation remains authorized by its RPC.
bool moduleNavigationAllowed(
  String page,
  ClinicMembership? member,
  ModuleAccess? access,
) {
  if (member == null || access == null) return true;
  return switch (page) {
    'Pacientes' => access.module('patients'),
    'Servicios' ||
    'Proveedores' ||
    'Agenda telefónica' ||
    'Promociones' ||
    'Productividad y semana' ||
    'Agenda' ||
    'Equipo y avisos' ||
    'Anuncios y avisos' ||
    'Pendientes del equipo' => access.module('agenda'),
    'Hospitalización' => access.module('hospital'),
    'Inventario' || 'Escanear producto' => access.module('inventory'),
    'Caja' || 'Planeación financiera' => access.module('sales'),
    'Receta' => access.module('prescriptions'),
    'Formatos' => access.module('forms') || access.module('clinical'),
    'Estadísticas' => access.module('statistics'),
    'Respaldo' || 'Estadísticas y respaldo' => access.module('backup'),
    _ => true,
  };
}
