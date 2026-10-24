import 'dart:math' as math;
import '../../doses/domain/quantity.dart';
import 'calculation_engine.dart';

class FluidPlan {
  FluidPlan(this.values, this.losses, this.weight);
  final Map<String, Quantity> values;
  final Quantity losses, weight;
  Quantity get rate => values['rate']!;
  Quantity get perMinute => rate / Quantity.parse('60');
  Quantity drops(int factor) => perMinute * Quantity.parse('$factor');
  Quantity? secondsPerDrop(int factor) =>
      drops(factor).positive ? Quantity.parse('60') / drops(factor) : null;
  Quantity potassiumRate(Quantity base, Quantity added) {
    if (base.n < BigInt.zero || added.n < BigInt.zero) {
      throw const FormatException('El potasio no puede ser negativo.');
    }
    return add(base, added) * rate / Quantity.parse('1000') / weight;
  }

  static FluidPlan calculate(
    Map<String, String> raw, {
    bool lossesPerDay = false,
    bool allometric = false,
  }) {
    final inputs = raw.map(
      (key, value) => MapEntry(key, Quantity.parse(value.replaceAll(',', '.'))),
    );
    Quantity required(String key) =>
        inputs[key] ?? (throw FormatException('Falta $key.'));
    final weight = required('weight');
    final hours = required('hours');
    if (!weight.positive || !hours.positive) {
      throw const FormatException('Peso y horas deben ser positivos.');
    }
    if (allometric) {
      final coefficient = required('coefficient');
      final exponent = required('exponent');
      if (!coefficient.positive ||
          !exponent.positive ||
          exponent.compareTo(Quantity.parse('1')) > 0) {
        throw const FormatException(
          'Coeficiente positivo y exponente entre 0 y 1 requeridos.',
        );
      }
      double number(Quantity q) => q.n.toDouble() / q.d.toDouble();
      final daily =
          number(coefficient) * math.pow(number(weight), number(exponent));
      if (!daily.isFinite || daily <= 0) {
        throw const FormatException('Resultado alométrico fuera de rango.');
      }
      final approximate = daily.toStringAsFixed(9);
      if (!Quantity.parse(approximate).positive) {
        throw const FormatException(
          'Resultado demasiado pequeño para la precisión alométrica.',
        );
      }
      inputs['maintenance'] = Quantity.parse(approximate) / weight;
    }
    final losses = lossesPerDay
        ? required('losses') * hours / Quantity.parse('24')
        : required('losses');
    final result = const CalculationEngine().calculate('fluids', {
      ...inputs,
      'losses': losses,
    });
    return FluidPlan(result.values, losses, weight);
  }

  static ({Quantity volume, Quantity rate}) bolus(
    Quantity weight,
    Quantity dose,
    Quantity minutes,
  ) {
    if (!weight.positive || !dose.positive || !minutes.positive) {
      throw const FormatException(
        'Peso, dosis de bolo y minutos deben ser positivos.',
      );
    }
    final volume = weight * dose;
    return (volume: volume, rate: volume * Quantity.parse('60') / minutes);
  }
}
