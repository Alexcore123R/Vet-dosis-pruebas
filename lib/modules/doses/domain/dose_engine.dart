import 'catalog.dart';
import 'quantity.dart';

class DoseResult {
  DoseResult(this.mass, this.volume, this.roundedVolume, this.alerts);
  final Quantity mass, volume, roundedVolume;
  final List<String> alerts;
  bool get canConfirm => alerts.isEmpty;
}

class DoseEngine {
  const DoseEngine();
  DoseResult calculate({
    required DrugDose drug,
    required Presentation presentation,
    required Quantity weightKg,
    required Quantity doseMgKg,
    required Quantity? syringeStepMl,
    String breed = '',
    List<String> conditions = const [],
  }) {
    if (!weightKg.positive ||
        !doseMgKg.positive ||
        (syringeStepMl != null && !syringeStepMl.positive)) {
      throw const FormatException(
        'Peso, dosis y graduación deben ser mayores que cero.',
      );
    }
    if (!drug.presentations.contains(presentation)) {
      throw const FormatException('La presentación no corresponde al fármaco.');
    }
    final concentration = presentation.concentration;
    if (concentration == null) {
      throw const FormatException(
        'Falta la concentración de esta presentación.',
      );
    }
    final mass = weightKg * doseMgKg;
    final volume = mass / concentration;
    final rounded = syringeStepMl == null
        ? volume
        : volume.nearestStep(syringeStepMl);
    final deliveredDose = rounded * concentration / weightKg;
    final alerts = <String>[];
    if (drug.min == null || drug.max == null) {
      alerts.add('Falta el rango de dosis publicado.');
    }
    if (!drug.evidence.verified || !presentation.evidence.verified) {
      alerts.add('Fuente clínica o presentación sin verificar.');
    }
    if (drug.route == null || drug.interval == null) {
      alerts.add('Falta la vía o el intervalo.');
    }
    if (drug.min != null && doseMgKg.compareTo(drug.min!) < 0) {
      alerts.add('Dosis por debajo del mínimo.');
    }
    if (drug.max != null && doseMgKg.compareTo(drug.max!) > 0) {
      alerts.add('Dosis por encima del máximo.');
    }
    if (syringeStepMl != null && !rounded.positive) {
      alerts.add('La graduación produce un volumen de cero.');
    }
    if ((drug.min != null && deliveredDose.compareTo(drug.min!) < 0) ||
        (drug.max != null && deliveredDose.compareTo(drug.max!) > 0)) {
      alerts.add(
        'El redondeo sale del rango permitido: cambia la graduación o la dosis.',
      );
    }
    for (final rule in drug.contraindications) {
      final value = rule.value.toLowerCase().trim();
      final matches = switch (rule.kind) {
        'especie' => drug.species.toLowerCase() == value,
        'raza' => breed.toLowerCase().trim() == value,
        _ => conditions.any((c) => c.toLowerCase().trim() == value),
      };
      if (matches) {
        alerts.add(
          'Contraindicación${rule.evidence.verified ? '' : ' sin verificar'}: ${rule.note}',
        );
      }
    }
    return DoseResult(mass, volume, rounded, List.unmodifiable(alerts));
  }
}

/// Personal entries remain separate; this validates a draft, not clinical truth.
List<String> validatePersonalDose(DrugDose draft, {DrugDose? general}) {
  final errors = <String>[];
  if (!draft.personal) errors.add('La entrada debe tener origen personal.');
  if (draft.min == null ||
      draft.max == null ||
      draft.route == null ||
      draft.interval == null ||
      draft.presentations.isEmpty ||
      draft.presentations.any((p) => p.concentration == null)) {
    errors.add(
      'Completa rango, vía, intervalo y concentración por presentación.',
    );
  }
  if (draft.min != null &&
      draft.max != null &&
      draft.min!.compareTo(draft.max!) > 0) {
    errors.add('Rango inválido.');
  }
  if (general?.max != null &&
      draft.max != null &&
      draft.max!.compareTo(general!.max! * Quantity.parse('100')) >= 0) {
    errors.add(
      'La dosis alcanza 100 veces el máximo de la base general; requiere revisión.',
    );
  }
  return errors;
}
