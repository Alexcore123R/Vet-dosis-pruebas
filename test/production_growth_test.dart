import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/production/domain/growth_calculation.dart';
import 'package:vetdosis_pro/modules/production/presentation/growth_panel.dart';

void main() {
  test('Documented example uses live weight gain, not carcass cost', () {
    final r = GrowthCalculation(
      animals: 10,
      days: 100,
      initialKg: 120,
      finalKg: 856,
      consumedKg: 2320,
      feedCost: 2320 * 2.6,
    );
    expect(r.gainKg, 736);
    expect(r.dailyPerAnimalKg, closeTo(.736, .000001));
    expect(r.conversion, closeTo(3.1521739, .000001));
    expect(r.costPerGainKg, closeTo(8.1956522, .000001));
  });

  test(
    'Rejects undefined ratios and nonfinite inputs; missing cost stays unknown',
    () {
      for (final weight in [120.0, 100.0, double.infinity, double.nan]) {
        expect(
          () => GrowthCalculation(
            animals: 10,
            days: 100,
            initialKg: 120,
            finalKg: weight,
            consumedKg: 2320,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => GrowthCalculation(
          animals: 0,
          days: 100,
          initialKg: 120,
          finalKg: 856,
          consumedKg: 2320,
        ),
        throwsFormatException,
      );
      expect(
        () => GrowthCalculation(
          animals: 10,
          days: 0,
          initialKg: 120,
          finalKg: 856,
          consumedKg: 2320,
        ),
        throwsFormatException,
      );
      final r = GrowthCalculation(
        animals: 10,
        days: 100,
        initialKg: 120,
        finalKg: 856,
        consumedKg: 2320,
      );
      expect(r.costPerGainKg, isNull);
    },
  );

  testWidgets(
    'Requires comparable group, clears stale result, removes revoked cost',
    (tester) async {
      Widget app(bool costs) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: GrowthPanel(showCosts: costs)),
        ),
      );
      await tester.pumpWidget(app(true));
      for (final (i, value) in [
        '10',
        '100',
        '120',
        '856',
        '2320',
        '6032',
      ].indexed) {
        await tester.enterText(find.byKey(ValueKey('growth-input-$i')), value);
      }
      final button = find.text('Calcular indicadores');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.textContaining('Confirma que'), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(
        find.textContaining('Conversión alimenticia: 3.152'),
        findsOneWidget,
      );
      expect(find.textContaining('8.20 MXN'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('growth-input-4')),
        '2300,5',
      );
      await tester.pump();
      expect(find.textContaining('Conversión alimenticia:'), findsNothing);
      await tester.pumpWidget(app(false));
      expect(find.byKey(const ValueKey('growth-input-5')), findsNothing);
      expect(find.textContaining('8.20 MXN'), findsNothing);
      await tester.pumpWidget(app(true));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('growth-input-5')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
