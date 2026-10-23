import 'quantity.dart';

/// Proportional arithmetic from a specific manufacturer's PACKAGE label.
/// This is intentionally separate from the generic mg/kg drug engine.
/// Weight-band instructions, fixed per-animal doses and multi-step schedules
/// must NOT be converted to this rule.
enum CommercialPackageUnit {
  ml('mL'),
  tablet('tableta(s)'),
  capsule('cápsula(s)'),
  drops('gota(s)'),
  sachet('sobre(s)'),
  gram('g'),
  milligram('mg'),
  internationalUnits('UI');

  const CommercialPackageUnit(this.label);
  final String label;
}

class TabletBreakdown {
  const TabletBreakdown({
    required this.exactAmount,
    required this.allowedParts,
    required this.wholeTablets,
    required this.fractionNumerator,
    required this.fractionDenominator,
    required this.exactlyDivisible,
  });

  final Quantity exactAmount;
  /// 1: enteras, 2: mitades, 4: cuartos, 8: octavos.
  /// Values greater than 1 require confirmation from this product's label.
  final int allowedParts;
  final BigInt wholeTablets;
  final int fractionNumerator;
  final int fractionDenominator;
  final bool exactlyDivisible;

  static TabletBreakdown from(Quantity amount, {int allowedParts = 1}) {
    if (!const [1, 2, 4, 8].contains(allowedParts)) {
      throw const FormatException('División de tableta no permitida.');
    }
    final parts = amount.n * BigInt.from(allowedParts);
    final integerPieces = parts ~/ amount.d;
    final exact = parts % amount.d == BigInt.zero;
    // Never round the result to a pill fraction.
    if (!exact) {
      return TabletBreakdown(
        exactAmount: amount,
        allowedParts: allowedParts,
        wholeTablets: BigInt.zero,
        fractionNumerator: 0,
        fractionDenominator: 1,
        exactlyDivisible: false,
      );
    }
    final whole = integerPieces ~/ BigInt.from(allowedParts);
    final remainder = (integerPieces % BigInt.from(allowedParts)).toInt();
    if (remainder == 0) {
      return TabletBreakdown(
        exactAmount: amount,
        allowedParts: allowedParts,
        wholeTablets: whole,
        fractionNumerator: 0,
        fractionDenominator: 1,
        exactlyDivisible: true,
      );
    }
    int a = remainder, b = allowedParts;
    while (b != 0) {
      final tmp = a % b;
      a = b;
      b = tmp;
    }
    return TabletBreakdown(
      exactAmount: amount,
      allowedParts: allowedParts,
      wholeTablets: whole,
      fractionNumerator: remainder ~/ a,
      fractionDenominator: allowedParts ~/ a,
      exactlyDivisible: true,
    );
  }

  String get descriptiveQuantity {
    if (!exactlyDivisible) {
      return '${exactAmount.display(places: 9)} tabletas';
    }
    final whole = wholeTablets == BigInt.zero
        ? ''
        : '$wholeTablets ${wholeTablets == BigInt.one ? 'tableta' : 'tabletas'}';
    final fractional = fractionNumerator == 0
        ? ''
        : '$fractionNumerator/$fractionDenominator de tableta';
    if (whole.isEmpty) return fractional;
    if (fractional.isEmpty) return whole;
    return '$whole + $fractional';
  }

  String? get fractionWarning => exactlyDivisible
      ? null
      : 'La cantidad exacta no puede expresarse con las fracciones '
        'de tableta autorizadas. No redondear ni partirla de otra forma.';
}

class CommercialPackageDose {
  const CommercialPackageDose({
    required this.productName,
    required this.presentation,
    required this.labelInstruction,
    required this.quantityOnLabel,
    required this.forWeightKg,
    required this.unit,
  });

  final String productName;
  final String presentation;
  final String labelInstruction;
  final Quantity quantityOnLabel;
  final Quantity forWeightKg;
  final CommercialPackageUnit unit;

  CommercialPackageResult calculate(
    Quantity animalWeightKg, {
    int tabletPartsAllowed = 1,
  }) {
    if (productName.trim().isEmpty ||
        presentation.trim().isEmpty ||
        labelInstruction.trim().isEmpty) {
      throw const FormatException(
        'Identifica producto, presentación y posología literal del empaque.',
      );
    }
    if (!animalWeightKg.positive ||
        !quantityOnLabel.positive ||
        !forWeightKg.positive) {
      throw const FormatException(
        'Peso, cantidad del empaque y kg de referencia deben ser positivos.',
      );
    }
    final result = animalWeightKg * quantityOnLabel / forWeightKg;
    return CommercialPackageResult(
      amount: result,
      unit: unit,
      tablets: unit == CommercialPackageUnit.tablet
          ? TabletBreakdown.from(result, allowedParts: tabletPartsAllowed)
          : null,
    );
  }
}

class CommercialPackageResult {
  const CommercialPackageResult({
    required this.amount,
    required this.unit,
    required this.tablets,
  });

  final Quantity amount;
  final CommercialPackageUnit unit;
  final TabletBreakdown? tablets;

  bool get tabletFractionRepresentable =>
      tablets?.exactlyDivisible ?? true;

  String get quantityText => tablets?.descriptiveQuantity ??
      '${amount.display(places: 9)} ${unit.label}';
}
