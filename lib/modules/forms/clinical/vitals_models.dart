import '../../doses/domain/quantity.dart';
import 'clinical_models.dart';

const vitalMucosaColors = {
  'rosadas': 'Rosadas',
  'palidas': 'Pálidas',
  'cianoticas': 'Cianóticas',
  'ictericas': 'Ictéricas',
  'congestivas': 'Congestivas',
};

const vitalMucosaHumidity = {
  'humedas': 'Húmedas',
  'pegajosas': 'Pegajosas',
  'secas': 'Secas',
};

String? normalizeVitalNumber(String? raw, String kind) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  return clinicalNumber(text, kind);
}

Quantity _add(Quantity a, Quantity b) =>
    Quantity(a.n * b.d + b.n * a.d, a.d * b.d);

String? calculatedPam(String? systolic, String? diastolic) {
  final s = systolic?.trim() ?? '', d = diastolic?.trim() ?? '';
  if (s.isEmpty && d.isEmpty) return null;
  if (s.isEmpty || d.isEmpty) {
    throw const FormatException(
      'Captura presión sistólica y diastólica para calcular la PAM.',
    );
  }
  final sbp = Quantity.parse(s.replaceAll(',', '.'));
  final dbp = Quantity.parse(d.replaceAll(',', '.'));
  final total = _add(sbp, dbp * Quantity.parse('2'));
  return (total / Quantity.parse('3')).display(places: 1);
}

Map<String, dynamic> validateVitalSet({
  required Map<String, String?> values,
  required String performedBy,
  required DateTime observedAt,
  String? mucosaColor,
  String? mucosaHumidity,
  String notes = '',
}) {
  final out = <String, dynamic>{
    'observed_at': observedAt.toUtc().toIso8601String(),
    'performed_by': performedBy,
  };
  for (final entry in const {
    'fc': 'fc',
    'fr': 'fr',
    'temperature': 'temperature',
    'tllc': 'tllc',
    'bp_systolic': 'bp_systolic',
    'bp_diastolic': 'bp_diastolic',
  }.entries) {
    final value = normalizeVitalNumber(values[entry.key], entry.value);
    if (value != null) out[entry.key] = value;
  }
  final hasSystolic = out.containsKey('bp_systolic');
  final hasDiastolic = out.containsKey('bp_diastolic');
  if (hasSystolic != hasDiastolic) {
    throw const FormatException(
      'Captura presión sistólica y diastólica juntas.',
    );
  }
  if (mucosaColor != null) {
    if (!vitalMucosaColors.containsKey(mucosaColor)) {
      throw const FormatException('Color de mucosas no compatible.');
    }
    out['mucosa_color'] = mucosaColor;
  }
  if (mucosaHumidity != null) {
    if (!vitalMucosaHumidity.containsKey(mucosaHumidity)) {
      throw const FormatException('Humedad de mucosas no compatible.');
    }
    out['mucosa_humidity'] = mucosaHumidity;
  }
  final cleanNotes = notes.trim();
  if (cleanNotes.length > 4000) {
    throw const FormatException('Las observaciones superan 4000 caracteres.');
  }
  if (cleanNotes.isNotEmpty) out['notes'] = cleanNotes;
  if (out.length == 2) {
    throw const FormatException('Captura al menos una constante o hallazgo.');
  }
  return Map.unmodifiable(out);
}

String speciesLabel(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.contains('can')) return 'Canino';
  if (s.contains('fel') || s.contains('gat')) return 'Felino';
  if (s.contains('equin') || s.contains('caball')) return 'Equino';
  if (s.contains('bovin') || s.contains('vaca')) return 'Bovino';
  if (s.contains('porcin') || s.contains('cerd')) return 'Porcino';
  if (s.contains('ovin')) return 'Ovino';
  if (s.contains('caprin')) return 'Caprino';
  if (s.contains('conej')) return 'Conejo';
  if (s.contains('ave') || s.contains('avian')) return 'Aves';
  if (s.contains('rept')) return 'Reptil';
  return raw.trim().isEmpty ? 'Especie no registrada' : raw.trim();
}
