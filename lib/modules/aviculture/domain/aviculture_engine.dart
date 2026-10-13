import '../../doses/domain/quantity.dart';

class AvicultureEngine {
  const AvicultureEngine();
  static final squareCmPerSquareM = Quantity.parse('10000');
  void positive(Quantity value) {
    if (!value.positive) {
      throw const FormatException('Usa valores mayores que cero.');
    }
  }

  BigInt integer(Quantity value) {
    positive(value);
    if (value.n % value.d != BigInt.zero) {
      throw const FormatException(
        'Aves, pisos, módulos y casetas deben ser enteros.',
      );
    }
    return value.n ~/ value.d;
  }

  Quantity reciprocalSpace(Quantity densityOrSpace) {
    positive(densityOrSpace);
    return squareCmPerSquareM / densityOrSpace;
  }

  BigInt floor(Quantity value) => value.n ~/ value.d;
  BigInt ceil(Quantity value) => (value.n + value.d - BigInt.one) ~/ value.d;
  Quantity upward(Quantity value, Quantity step) {
    positive(step);
    return Quantity(ceil(value / step), BigInt.one) * step;
  }

  Quantity areaPerBird(Quantity design, String unit) {
    positive(design);
    return switch (unit) {
      'cm2' => design,
      'aves_por_m2' => reciprocalSpace(design),
      _ => throw const FormatException('Unidad de superficie no compatible.'),
    };
  }

  Quantity usableArea(Quantity length, Quantity width, String dimensionUnit) {
    positive(length);
    positive(width);
    return switch (dimensionUnit) {
      'cm' => length * width,
      'm' => length * width * squareCmPerSquareM,
      _ => throw const FormatException('Elige dimensiones en cm o m.'),
    };
  }

  BigInt capacity(
    Quantity unitAreaCm2,
    Quantity design,
    String unit, {
    required Quantity floors,
    required Quantity modules,
    required Quantity houses,
  }) {
    positive(unitAreaCm2);
    // Floor each independent usable surface, never pool leftover cage space.
    return floor(unitAreaCm2 / areaPerBird(design, unit)) *
        integer(floors) *
        integer(modules) *
        integer(houses);
  }

  Quantity requiredArea(Quantity birds, Quantity design, String unit) {
    integer(birds);
    return birds * areaPerBird(design, unit);
  }

  Quantity linearMeters(
    Quantity birds,
    Quantity cmPerBird,
    Quantity stepMeters,
  ) {
    integer(birds);
    positive(cmPerBird);
    return upward(birds * cmPerBird / Quantity.parse('100'), stepMeters);
  }

  BigInt equipment(Quantity birds, Quantity birdsPerUnit) {
    integer(birds);
    positive(birdsPerUnit);
    return ceil(birds / birdsPerUnit);
  }
}
