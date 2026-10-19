/// Comparable, closed group over one period: no entries, exits or deaths.
class GrowthCalculation {
  GrowthCalculation({
    required this.animals,
    required this.days,
    required this.initialKg,
    required this.finalKg,
    required this.consumedKg,
    this.feedCost,
  }) {
    final values = [initialKg, finalKg, consumedKg, ?feedCost];
    if (animals <= 0 ||
        days <= 0 ||
        values.any((v) => !v.isFinite || v < 0) ||
        initialKg <= 0 ||
        finalKg <= initialKg ||
        consumedKg <= 0) {
      throw const FormatException(
        'Revisa los datos: animales y días enteros positivos, pesos y consumo positivos, '
        'y peso final mayor al inicial. El costo puede ser cero.',
      );
    }
    if (![
      gainKg,
      dailyPerAnimalKg,
      conversion,
      ?costPerGainKg,
    ].every((v) => v.isFinite && v >= 0)) {
      throw const FormatException('Los valores exceden el rango de cálculo.');
    }
  }

  final int animals, days;
  final double initialKg, finalKg, consumedKg;
  final double? feedCost;
  double get gainKg => finalKg - initialKg;
  double get dailyPerAnimalKg => gainKg / animals / days;
  double get conversion => consumedKg / gainKg;
  double? get costPerGainKg => feedCost == null ? null : feedCost! / gainKg;
}
