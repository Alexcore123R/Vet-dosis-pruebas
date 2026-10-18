/// Monthly scenario in minor currency units. No ledger or remote data is used.
class FinancialPlan {
  FinancialPlan({
    required this.income,
    required this.fixedCosts,
    required this.variableCosts,
    required this.depreciation,
    required this.investment,
    required this.availableFunds,
    required this.reserve,
  }) {
    for (final amount in [
      income,
      fixedCosts,
      variableCosts,
      depreciation,
      investment,
      availableFunds,
      reserve,
    ]) {
      if (amount < 0 || amount > 100000000000) {
        throw ArgumentError('Importe fuera de rango.');
      }
    }
  }
  final int income, fixedCosts, variableCosts, depreciation;
  final int investment, availableFunds, reserve;
  int get operatingCash => income - fixedCosts - variableCosts;
  int get estimatedResult => operatingCash - depreciation;
  // Funds for investment, one month of cash costs and contingency, less funds
  // available. Projected receipts are not treated as cash already available.
  int get fundingGap =>
      (investment + fixedCosts + variableCosts + reserve - availableFunds)
          .clamp(0, 400000000000);
  double? get breakEvenIncome => income > variableCosts
      ? (fixedCosts + depreciation) / (1 - variableCosts / income)
      : null;
  double? get recoveryMonths =>
      operatingCash > 0 ? investment / operatingCash : null;
}

/// Spanish decimal comma or decimal point; grouping separators are disallowed.
int? parsePlanAmount(String input) {
  final text = input.trim();
  if (!RegExp(r'^\d{1,10}([.,]\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.replaceAll(',', '.').split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return cents <= 100000000000 ? cents : null;
}
