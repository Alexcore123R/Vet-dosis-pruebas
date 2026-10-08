/// Exact rational arithmetic for entered decimal quantities. No binary rounding.
class Quantity implements Comparable<Quantity> {
  Quantity(this.n, this.d) {
    if (d <= BigInt.zero) throw ArgumentError('Denominador inválido');
  }
  final BigInt n;
  final BigInt d;
  factory Quantity.parse(String value) {
    final text = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,12}(\.\d{1,9})?$').hasMatch(text)) {
      throw const FormatException(
        'Ingresa un número positivo sin separadores de miles.',
      );
    }
    final parts = text.split('.');
    final scale = parts.length == 2 ? parts[1].length : 0;
    return Quantity(BigInt.parse(parts.join()), BigInt.from(10).pow(scale));
  }
  Quantity operator *(Quantity other) => Quantity(n * other.n, d * other.d);
  Quantity operator /(Quantity other) {
    if (!other.positive) {
      throw const FormatException('La concentración debe ser mayor que cero.');
    }
    return Quantity(n * other.d, d * other.n);
  }

  bool get positive => n > BigInt.zero;
  @override
  int compareTo(Quantity other) => (n * other.d).compareTo(other.n * d);
  Quantity nearestStep(Quantity step) {
    if (!step.positive) {
      throw const FormatException('La graduación debe ser mayor que cero.');
    }
    final ratio = this / step;
    final count = (ratio.n * BigInt.two + ratio.d) ~/ (ratio.d * BigInt.two);
    return Quantity(count, BigInt.one) * step;
  }

  /// Display only. Decisions always use the exact fraction.
  String display({int places = 6}) {
    final scale = BigInt.from(10).pow(places);
    final rounded = (n * scale * BigInt.two + d) ~/ (d * BigInt.two);
    final digits = rounded.toString().padLeft(places + 1, '0');
    final whole = digits.substring(0, digits.length - places);
    final fraction = digits
        .substring(digits.length - places)
        .replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? whole : '$whole,$fraction';
  }
}
