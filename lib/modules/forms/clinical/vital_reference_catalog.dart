import 'dart:convert';

import '../../doses/domain/quantity.dart';
import 'vitals_models.dart';

enum VitalReferenceState { below, within, above }

class VitalReferenceEntry {
  const VitalReferenceEntry({
    required this.id,
    required this.species,
    required this.parameter,
    required this.unit,
    required this.min,
    required this.max,
    required this.source,
    required this.reviewedAt,
    required this.verified,
  });

  final String id;
  final String species;
  final String parameter;
  final String unit;
  final Quantity min;
  final Quantity max;
  final String source;
  final DateTime reviewedAt;
  final bool verified;

  VitalReferenceState evaluate(Quantity value) {
    if (!verified) {
      throw const FormatException(
        'Una referencia sin verificar no puede clasificar constantes.',
      );
    }
    if (value.compareTo(min) < 0) return VitalReferenceState.below;
    if (value.compareTo(max) > 0) return VitalReferenceState.above;
    return VitalReferenceState.within;
  }
}

class VitalReferenceEvaluation {
  const VitalReferenceEvaluation({
    required this.entry,
    required this.state,
  });

  final VitalReferenceEntry entry;
  final VitalReferenceState state;

  String get label {
    switch (state) {
      case VitalReferenceState.below:
        return 'Por debajo de referencia';
      case VitalReferenceState.within:
        return 'Dentro de referencia';
      case VitalReferenceState.above:
        return 'Por encima de referencia';
    }
  }
}

class VitalReferenceCatalog {
  const VitalReferenceCatalog({
    required this.version,
    required this.entries,
  });

  final String version;
  final List<VitalReferenceEntry> entries;

  factory VitalReferenceCatalog.parse(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic> || raw['schema_version'] != 1) {
      throw const FormatException(
        'Versión de catálogo de constantes no compatible.',
      );
    }
    final version = _requiredText(raw, 'catalog_version');
    final list = raw['references'];
    if (list is! List ||
        list.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('references debe ser una lista de objetos.');
    }
    final entries = list
        .cast<Map<String, dynamic>>()
        .map(_readEntry)
        .toList(growable: false);
    if (entries.map((entry) => entry.id).toSet().length != entries.length) {
      throw const FormatException(
        'Hay identificadores de referencia duplicados.',
      );
    }
    return VitalReferenceCatalog(
      version: version,
      entries: List.unmodifiable(entries),
    );
  }

  VitalReferenceEvaluation? evaluate({
    required String species,
    required String parameter,
    required String? rawValue,
  }) {
    final valueText = rawValue?.trim() ?? '';
    if (valueText.isEmpty) return null;

    final normalizedSpecies = speciesLabel(species).toLowerCase();
    final matches = entries
        .where(
          (entry) =>
              entry.verified &&
              speciesLabel(entry.species).toLowerCase() == normalizedSpecies &&
              entry.parameter == parameter,
        )
        .toList(growable: false);
    if (matches.length != 1) return null;

    final value = Quantity.parse(valueText.replaceAll(',', '.'));
    return VitalReferenceEvaluation(
      entry: matches.single,
      state: matches.single.evaluate(value),
    );
  }

  static VitalReferenceEntry _readEntry(Map<String, dynamic> raw) {
    final min = _quantity(raw, 'min');
    final max = _quantity(raw, 'max');
    if (min.compareTo(max) > 0) {
      throw const FormatException('Rango de referencia invertido.');
    }
    final status = _requiredText(raw, 'status');
    if (status != 'verified' && status != 'unverified') {
      throw const FormatException('Estado de referencia inválido.');
    }
    final source = _requiredText(raw, 'source');
    final reviewed = DateTime.tryParse(_requiredText(raw, 'reviewed_at'));
    if (reviewed == null) {
      throw const FormatException('Fecha de revisión inválida.');
    }
    return VitalReferenceEntry(
      id: _requiredText(raw, 'id'),
      species: _requiredText(raw, 'species'),
      parameter: _requiredText(raw, 'parameter'),
      unit: _requiredText(raw, 'unit'),
      min: min,
      max: max,
      source: source,
      reviewedAt: reviewed.toUtc(),
      verified: status == 'verified',
    );
  }

  static Quantity _quantity(Map<String, dynamic> raw, String key) {
    final value = raw[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key debe ser un decimal entre comillas.');
    }
    return Quantity.parse(value.trim());
  }

  static String _requiredText(Map<String, dynamic> raw, String key) {
    final value = raw[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Falta $key.');
    }
    return value.trim();
  }
}
