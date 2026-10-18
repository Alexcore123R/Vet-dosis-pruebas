/// Destinations reuse the host routes; this catalog does not grant permissions.
class SectionGroup {
  const SectionGroup(this.title, this.pages, {this.planned = const []});
  final String title;
  final List<String> pages;
  final List<String> planned;
}

const sectionGroups = [
  SectionGroup('Atención y expedientes', [
    'Agenda',
    'Pacientes',
    'Hospitalización',
    'Receta',
    'Formatos',
  ]),
  SectionGroup('Medicamentos y herramientas', [
    'Cálculo rápido',
    'Cálculos clínicos',
    'Inventario',
    'Escanear producto',
  ]),
  SectionGroup('Administración y finanzas', [
    'Caja',
    'Planeación financiera',
    'Servicios',
    'Proveedores',
  ]),
  SectionGroup('Equipo y comunicación', [
    'Equipo y avisos',
    'Pendientes del equipo',
    'Checado',
  ]),
  SectionGroup('Estadísticas y reportes', ['Estadísticas']),
  SectionGroup('Asistente IA', ['Asistente IA']),
  SectionGroup('Cuenta y ajustes', [
    'Mi cuenta y clínicas',
    'Ajustes',
    'Respaldo',
    'Planes',
    'Producto y costos',
    'Inicio guiado',
    'Ayuda y soporte',
  ]),
];

String normalizeSection(String value) {
  var result = value.toLowerCase().trim();
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
  for (final pair in accents.entries) {
    result = result.replaceAll(pair.key, pair.value);
  }
  return result;
}
