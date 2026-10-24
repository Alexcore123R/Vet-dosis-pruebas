import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/calculations/domain/fluid_plan.dart';
import 'package:vetdosis_pro/modules/doses/domain/quantity.dart';

Map<String, String> inputs() => {
  'weight': '28.5',
  'maintenance': '60',
  'percent': '5',
  'hours': '24',
  'losses': '100',
  'drop_factor': '20',
};
void main() {
  test('Reference arithmetic and both administration equipment factors', () {
    final p = FluidPlan.calculate(inputs());
    expect(p.values['total']!.display(), '3235');
    expect(p.values['deficit']!.display(), '1425');
    expect(p.drops(60).compareTo(p.rate), 0);
    expect(p.drops(20).compareTo(p.rate / Quantity.parse('3')), 0);
    expect(
      p.secondsPerDrop(20)!.compareTo(Quantity.parse('60') / p.drops(20)),
      0,
    );
  });
  test(
    'Daily losses scaled to actual duration; period losses kept unchanged',
    () {
      final daily = FluidPlan.calculate({
        ...inputs(),
        'hours': '12',
      }, lossesPerDay: true);
      final period = FluidPlan.calculate({...inputs(), 'hours': '12'});
      expect(daily.losses.display(), '50');
      expect(period.losses.display(), '100');
      expect(daily.values['total']!.display(), '2330');
      expect(period.values['total']!.display(), '2380');
    },
  );
  test('Zero flow cannot divide by zero or start a simulated drip', () {
    final p = FluidPlan.calculate({
      ...inputs(),
      'maintenance': '0',
      'percent': '0',
      'losses': '0',
    });
    expect(p.secondsPerDrop(60), isNull);
    expect(p.drops(20).positive, isFalse);
  });
  test('Potassium includes basal plus supplemental concentration', () {
    final p = FluidPlan.calculate({
      ...inputs(),
      'weight': '10',
      'maintenance': '240',
      'percent': '0',
      'losses': '0',
    });
    expect(
      p.potassiumRate(Quantity.parse('4'), Quantity.parse('20')).display(),
      '0,24',
    );
    expect(
      () => p.potassiumRate(Quantity.parse('-1'), Quantity.parse('20')),
      throwsFormatException,
    );
  });
  test('Bolus is separate; rejects zero duration', () {
    final b = FluidPlan.bolus(
      Quantity.parse('10'),
      Quantity.parse('2'),
      Quantity.parse('10'),
    );
    expect(b.volume.display(), '20');
    expect(b.rate.display(), '120');
    expect(
      () => FluidPlan.bolus(
        Quantity.parse('10'),
        Quantity.parse('2'),
        Quantity.parse('0'),
      ),
      throwsFormatException,
    );
  });
  test('Allometric custom coefficients, no automatic species constants', () {
    final p = FluidPlan.calculate({
      ...inputs(),
      'weight': '4',
      'coefficient': '10',
      'exponent': '0.5',
    }, allometric: true);
    expect(p.values['maintenance_day']!.display(), '20');
    expect(
      () => FluidPlan.calculate({
        ...inputs(),
        'coefficient': '10',
        'exponent': '2',
      }, allometric: true),
      throwsFormatException,
    );
  });
  test('Invalid period or dehydration is rejected', () {
    for (final entry in [
      {'hours': '0'},
      {'weight': '0'},
      {'percent': '100'},
      {'losses': '-2'},
      {'drop_factor': '0'},
    ]) {
      expect(
        () => FluidPlan.calculate({...inputs(), ...entry}),
        throwsFormatException,
      );
    }
  });
}
