class FeedingCalculation {
  FeedingCalculation({
    required this.animals,
    required this.averageGrams,
    required this.dailyPercent,
    required this.meals,
  }) {
    if (animals <= 0 ||
        meals <= 0 ||
        !averageGrams.isFinite ||
        averageGrams <= 0 ||
        !dailyPercent.isFinite ||
        dailyPercent < 0 ||
        dailyPercent > 100 ||
        !biomassKg.isFinite ||
        !dailyKg.isFinite ||
        !perMealKg.isFinite) {
      throw const FormatException(
        'Revisa cantidad de peces, peso positivo, porcentaje de 0 a 100 y número entero positivo de raciones.',
      );
    }
  }
  final int animals, meals;
  final double averageGrams, dailyPercent;
  double get biomassKg => animals * (averageGrams / 1000);
  double get dailyKg => biomassKg * (dailyPercent / 100);
  double get perMealKg => dailyKg / meals;
}
