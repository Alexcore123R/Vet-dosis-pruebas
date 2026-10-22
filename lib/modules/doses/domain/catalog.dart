import 'dart:convert';
import 'quantity.dart';

String requiredText(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Falta $key.');
  }
  return value.trim();
}

Quantity? optionalQuantity(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null || value == '') return null;
  // Strings preserve decimals and prohibit scientific notation/ambiguous units.
  if (value is! String) {
    throw FormatException('$key debe ser un decimal entre comillas.');
  }
  final number = Quantity.parse(value);
  if (!number.positive) throw FormatException('$key debe ser mayor que cero.');
  return number;
}

class Evidence {
  Evidence(this.source, this.verified);
  final String? source;
  final bool verified;
  factory Evidence.read(Map<String, dynamic> map) {
    final status = requiredText(map, 'estado');
    if (status != 'verificada' && status != 'sin verificar') {
      throw const FormatException('Estado de verificación inválido.');
    }
    final source = map['fuente'];
    if (source != null && source is! String) {
      throw const FormatException('Fuente inválida.');
    }
    if (status == 'verificada' &&
        (source == null || (source as String).trim().isEmpty)) {
      throw const FormatException('Una entrada verificada requiere fuente.');
    }
    return Evidence(source as String?, status == 'verificada');
  }
}

class Presentation {
  Presentation(this.id, this.brand, this.concentration, this.evidence);
  final String id, brand;
  final Quantity? concentration;
  final Evidence evidence;
  factory Presentation.read(Map<String, dynamic> map) {
    if (map['unidad_concentracion'] != 'mg/ml') {
      throw const FormatException(
        'Esta versión requiere concentración explícita en mg/ml.',
      );
    }
    return Presentation(
      requiredText(map, 'id'),
      requiredText(map, 'nombre_comercial'),
      optionalQuantity(map, 'concentracion'),
      Evidence.read(map),
    );
  }
}

class Contraindication {
  Contraindication(this.kind, this.value, this.note, this.evidence);
  final String kind, value, note;
  final Evidence evidence;
  factory Contraindication.read(Map<String, dynamic> map) {
    final kind = requiredText(map, 'tipo');
    if (!['especie', 'raza', 'condicion'].contains(kind)) {
      throw const FormatException('Tipo de contraindicación inválido.');
    }
    return Contraindication(
      kind,
      requiredText(map, 'valor'),
      requiredText(map, 'nota'),
      Evidence.read(map),
    );
  }
}

class DrugDose {
  DrugDose({
    required this.id,
    required this.name,
    required this.species,
    required this.min,
    required this.max,
    required this.route,
    required this.interval,
    required this.evidence,
    required this.presentations,
    required this.contraindications,
    this.personal = false,
  });
  final String id, name, species;
  final String? route, interval;
  final Quantity? min, max;
  final Evidence evidence;
  final List<Presentation> presentations;
  final List<Contraindication> contraindications;
  final bool personal;
  Quantity? get prescribedDose =>
      min != null && max != null && min!.compareTo(max!) == 0 ? min : null;
  factory DrugDose.read(Map<String, dynamic> map, {bool personal = false}) {
    if (map['unidad_dosis'] != 'mg/kg') {
      throw const FormatException(
        'Esta versión requiere dosis explícita en mg/kg.',
      );
    }
    final min = optionalQuantity(map, 'min'),
        max = optionalQuantity(map, 'max');
    if (min != null && max != null && min.compareTo(max) > 0) {
      throw const FormatException('El mínimo supera al máximo.');
    }
    String? optionalText(String key) {
      final value = map[key];
      if (value == null || value == '') return null;
      if (value is! String) throw FormatException('$key inválido.');
      return value.trim().isEmpty ? null : value.trim();
    }

    final presentations = readList(
      map,
      'presentaciones',
    ).map(Presentation.read).toList();
    if (presentations.map((p) => p.id).toSet().length != presentations.length) {
      throw const FormatException('Presentaciones duplicadas.');
    }
    return DrugDose(
      id: requiredText(map, 'id'),
      name: requiredText(map, 'farmaco'),
      species: requiredText(map, 'especie'),
      min: min,
      max: max,
      route: optionalText('via'),
      interval: optionalText('intervalo'),
      evidence: Evidence.read(map),
      presentations: List.unmodifiable(presentations),
      contraindications: List.unmodifiable(
        readList(map, 'contraindicaciones').map(Contraindication.read),
      ),
      personal: personal,
    );
  }
}

List<Map<String, dynamic>> readList(Map<String, dynamic> map, String key) {
  final list = map[key];
  if (list is! List || list.any((item) => item is! Map<String, dynamic>)) {
    throw FormatException('$key debe ser una lista de objetos.');
  }
  return list.cast<Map<String, dynamic>>();
}

class DoseCatalog {
  DoseCatalog(this.version, this.drugs);
  final String version;
  final List<DrugDose> drugs;
  factory DoseCatalog.parse(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic> || raw['schema_version'] != 1) {
      throw const FormatException('Versión de catálogo no compatible.');
    }
    final drugs = readList(
      raw,
      'farmacos',
    ).map((m) => DrugDose.read(m)).toList();
    if (drugs.map((d) => d.id).toSet().length != drugs.length) {
      throw const FormatException('Identificadores duplicados.');
    }
    return DoseCatalog(
      requiredText(raw, 'catalog_version'),
      List.unmodifiable(drugs),
    );
  }
  List<DrugDose> search(String text, {String? species}) {
    final query = text.toLowerCase().trim();
    return drugs
        .where(
          (d) =>
              (species == null || d.species == species) &&
              ('${d.name} ${d.presentations.map((p) => p.brand).join(' ')}')
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }
}
