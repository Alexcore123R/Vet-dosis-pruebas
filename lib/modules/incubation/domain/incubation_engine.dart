import '../../doses/domain/quantity.dart';

Quantity difference(Quantity a, Quantity b) =>
    Quantity(a.n * b.d - b.n * a.d, a.d * b.d);
String signedDisplay(Quantity q) => q.n < BigInt.zero
    ? '−${Quantity(-q.n, q.d).display(places: 9)}'
    : q.display(places: 9);

class IncubationEngine {
  const IncubationEngine();
  static final hundred = Quantity.parse('100');
  void positive(Quantity q) {
    if (!q.positive) {
      throw const FormatException('Usa valores mayores que cero.');
    }
  }

  void percent(Quantity q) {
    if (q.n < BigInt.zero || q.compareTo(hundred) > 0) {
      throw const FormatException('El porcentaje debe estar entre 0 y 100.');
    }
  }

  Quantity chickWeight(Quantity egg, Quantity yieldPercent) {
    positive(egg);
    positive(yieldPercent);
    percent(yieldPercent);
    return egg * yieldPercent / hundred;
  }

  Quantity lossPercent(Quantity initial, Quantity current) {
    positive(initial);
    positive(current);
    return difference(initial, current) / initial * hundred;
  }

  Quantity expectedEgg(Quantity initial, Quantity loss) {
    positive(initial);
    percent(loss);
    return initial * difference(hundred, loss) / hundred;
  }

  Quantity? lossAtDay(int day, Map<int, Quantity> curve) {
    if (day < 0) throw const FormatException('El día no puede ser negativo.');
    // Only documented points. Never interpolate or extrapolate.
    return curve[day];
  }

  /// Converts explicitly mass/volume concentrations into mg/ml.
  /// ppm m/m, %m/m and %v/v need other data; no density assumptions.
  Quantity massVolume(Quantity value, String unit) {
    positive(value);
    if (unit == 'percent_mv' && value.compareTo(hundred) > 0) {
      throw const FormatException('El porcentaje supera 100.');
    }
    return switch (unit) {
      'mg_ml' => value,
      'mg_l' || 'ppm_mg_l' => value / Quantity.parse('1000'),
      'percent_mv' => value * Quantity.parse('10'),
      _ => throw const FormatException(
        'Base incompatible o ambigua. Usa mg/ml, mg/L o % m/v. No se asume que ppm sea mg/L.',
      ),
    };
  }

  Quantity concentrateMl(
    Quantity stockMgMl,
    Quantity targetMgMl,
    Quantity finalMl,
  ) {
    positive(stockMgMl);
    positive(targetMgMl);
    positive(finalMl);
    if (targetMgMl.compareTo(stockMgMl) > 0) {
      throw const FormatException(
        'La concentración objetivo supera la inicial: no se obtiene por dilución.',
      );
    }
    return targetMgMl * finalMl / stockMgMl;
  }
}
