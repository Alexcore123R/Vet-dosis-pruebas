import '../../doses/domain/quantity.dart';

Quantity add(Quantity a, Quantity b) =>
    Quantity(a.n * b.d + b.n * a.d, a.d * b.d);
Quantity subtract(Quantity a, Quantity b) =>
    Quantity(a.n * b.d - b.n * a.d, a.d * b.d);

class CalculationResult {
  const CalculationResult(this.values, this.notes);
  final Map<String, Quantity> values;
  final List<String> notes;
}

/// Pure arithmetic. Parameters are supplied by the responsible professional,
/// never selected as clinical recommendations by this engine.
class CalculationEngine {
  const CalculationEngine();
  CalculationResult calculate(String id, Map<String, Quantity> inputs) {
    Quantity q(String name, {bool zero = false}) {
      final value = inputs[name];
      if (value == null ||
          value.n < BigInt.zero ||
          (!zero && !value.positive)) {
        throw FormatException(
          'Completa $name con un valor ${zero ? 'no negativo' : 'mayor que cero'}.',
        );
      }
      return value;
    }

    final thousand = Quantity.parse('1000');
    final hourMinutes = Quantity.parse('60');
    final dayHours = Quantity.parse('24');
    final notes = <String>[
      'Parámetros capturados; resultado matemático, no prescripción.',
    ];
    Map<String, Quantity> result;
    switch (id) {
      case 'fluids':
        final weight = q('weight');
        final percent = q('percent', zero: true);
        if (percent.compareTo(Quantity.parse('100')) >= 0) {
          throw const FormatException('El porcentaje debe ser menor que 100.');
        }
        final maintenance = weight * q('maintenance', zero: true);
        final deficit = weight * percent * Quantity.parse('10');
        final hours = q('hours');
        final total = add(
          add(maintenance * hours / dayHours, deficit),
          q('losses', zero: true),
        );
        final rate = total / hours;
        result = {
          'maintenance_day': maintenance,
          'deficit': deficit,
          'total': total,
          'rate': rate,
          'drops': rate * q('drop_factor') / hourMinutes,
        };
        notes.add(
          'Déficit estimado con 1 kg de agua ≈ 1000 ml. Pérdidas: volumen total del periodo, no ml/h.',
        );
      case 'cri':
        final weight = q('weight');
        final drugRate = weight * q('dose') * hourMinutes / thousand;
        final concentration = q('concentration');
        final volume = q('final_volume');
        final duration = volume / q('pump_rate');
        final mass = drugRate * duration;
        final drugVolume = mass / concentration;
        if (drugVolume.compareTo(volume) > 0) {
          throw const FormatException(
            'El volumen del fármaco supera el volumen FINAL de la mezcla.',
          );
        }
        result = {
          'mass_hour': drugRate,
          'duration': duration,
          'mass': mass,
          'drug_volume': drugVolume,
          'solvent_volume': subtract(volume, drugVolume),
          'mixture_concentration': mass / volume,
          'drops': q('pump_rate') * q('drop_factor') / hourMinutes,
        };
        notes.add(
          'El volumen final incluye el fármaco; retirar/ajustar diluyente hasta ese volumen. Compatibilidad y estabilidad requieren revisión.',
        );
      case 'herd':
        final count = q('count');
        if (count.n % count.d != BigInt.zero) {
          throw const FormatException('Número de animales entero.');
        }
        final mass = q('weight') * q('dose');
        final volume = mass / q('concentration');
        result = {
          'mass_head': mass,
          'volume_head': volume,
          'mass_lot': mass * count,
          'volume_lot': volume * count,
        };
        notes.add(
          'Peso por cabeza uniforme estimado; no sustituye pesos individuales.',
        );
      case 'water':
        final mass = q('target') * q('litres');
        result = {'mass': mass, 'product_grams': mass / q('strength')};
        notes.add(
          'Entrada explícita en mg/L. No se asume que toda etiqueta “ppm” sea mg/L ni se estima consumo por animal.',
        );
      case 'feed':
        final mass = q('target') * q('tonnes') * thousand;
        result = {'mass': mass, 'product_grams': mass / q('strength')};
        notes.add(
          'Concentración en mg de activo/kg de alimento; potencia del producto en mg/g. No se calcula ingesta por animal.',
        );
      case 'adjustment':
        final dose = q('dose') * q('factor');
        final mass = dose * q('weight');
        result = {
          'dose': dose,
          'mass': mass,
          'volume': mass / q('concentration'),
        };
        notes.add(
          'Factor capturado por el MVZ, sin recomendación por edad. Debe existir referencia aplicable al paciente y al fármaco.',
        );
      default:
        throw const FormatException('Cálculo no compatible.');
    }
    return CalculationResult(
      Map.unmodifiable(result),
      List.unmodifiable(notes),
    );
  }
}

String displayCalculation(Quantity value) {
  final text = value.display(places: 9);
  return value.positive && text == '0' ? '<0,000000001' : text;
}
