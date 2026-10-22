/// Service names from the rotativo, pp. 8–9; prices belong to each clinic.
const serviceCategories = <String, String>{
  'consulta': 'Consulta y seguimiento',
  'cirugia': 'Cirugías',
  'hospedaje': 'Hospedaje / pensión',
  'hospitalizacion': 'Hospitalización',
  'laboratorio': 'Laboratorio y análisis',
  'preventiva': 'Vacunas y desparasitación',
  'curaciones': 'Curaciones y retiro de puntos',
  'estetica': 'Baño y estética',
  'imagen': 'Diagnóstico por imágenes',
  'anestesia': 'Anestesia y manejo del dolor',
  'urgencias': 'Urgencias',
  'domicilio': 'Atención a domicilio',
  'guarderia': 'Guardería',
  'odontologia': 'Odontología',
  'rehabilitacion': 'Rehabilitación',
  'otro': 'Otros servicios',
};
const serviceExamples = <String, List<String>>{
  'consulta': ['Consulta clínica', 'Revisión / seguimiento'],
  'cirugia': ['Cirugía'],
  'hospedaje': ['Hospedaje / pensión'],
  'hospitalizacion': ['Hospitalización'],
  'laboratorio': [
    'Exámenes de laboratorio',
    'Hematología',
    'Bioquímica',
    'Citología',
    'Parasitología',
  ],
  'preventiva': ['Vacunación', 'Desparasitación'],
  'curaciones': ['Limpieza de heridas', 'Retiro de puntos'],
  'estetica': [
    'Baño',
    'Estética / peluquería',
    'Corte de uñas',
    'Limpieza de orejas',
  ],
  'imagen': [
    'Radiografía',
    'Ecografía',
    'Endoscopia',
    'Tomografía',
    'Resonancia magnética',
  ],
  'anestesia': ['Anestesia general', 'Anestesia regional', 'Manejo del dolor'],
  'urgencias': ['Consulta de urgencia'],
  'domicilio': ['Consulta a domicilio'],
  'guarderia': ['Guardería de día'],
  'odontologia': ['Consulta dental', 'Limpieza dental'],
  'rehabilitacion': ['Sesión de rehabilitación'],
  'otro': ['Servicio personalizado'],
};
String serviceCategory(Map<String, dynamic> service) =>
    serviceCategories.containsKey(service['category'])
    ? service['category'] as String
    : 'otro';

/// Suggestions are configurable labels, not procedures automatically offered.
const serviceSubcategories = <String, List<String>>{
  'consulta': ['General', 'Especializada', 'Seguimiento'],
  'cirugia': [
    'General y esterilización',
    'Oftálmica',
    'Oncológica',
    'Traumatología y ortopedia',
    'Endoscópica / laparoscópica',
  ],
  'laboratorio': [
    'Hematología',
    'Bioquímica',
    'Serología',
    'Parasitología',
    'Uroanálisis',
    'Cultivos y antibiogramas',
    'Citología y aspirados',
  ],
  'imagen': [
    'Radiología',
    'Ecografía',
    'Endoscopia',
    'Tomografía',
    'Resonancia magnética',
  ],
  'anestesia': [
    'General / inhalatoria',
    'Regional / epidural',
    'Monitorización',
    'Manejo del dolor',
  ],
  'hospitalizacion': ['General', 'Cuidados intensivos', 'Aislamiento'],
  'hospedaje': ['Canino', 'Felino', 'Otras especies'],
  'guarderia': ['Canina', 'Felina', 'Otras especies'],
  'preventiva': [
    'Vacunación',
    'Desparasitación interna',
    'Desparasitación externa',
  ],
  'estetica': ['Baño cosmético', 'Baño medicado', 'Peluquería', 'Uñas y oídos'],
  'curaciones': ['Heridas', 'Retiro de puntos'],
  'odontologia': ['Consulta dental', 'Procedimientos dentales'],
  'rehabilitacion': ['Valoración', 'Terapia'],
};
String serviceSubcategory(Map<String, dynamic> service) =>
    (service['subcategory'] as String? ?? '').trim();
