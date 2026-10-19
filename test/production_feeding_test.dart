import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/production/domain/feeding_calculation.dart';
import 'package:vetdosis_pro/modules/production/presentation/feeding_panel.dart';
import 'package:vetdosis_pro/modules/production/presentation/production_menu.dart';
import 'package:vetdosis_pro/modules/production/presentation/growth_panel.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'section_navigation_test.dart' show admin;
import 'support/fake_auth.dart' show member;

void main() {
  test(
    'Converts grams and percentage, divides portions, accepts explicit zero',
    () {
      final r = FeedingCalculation(
        animals: 1000,
        averageGrams: 200,
        dailyPercent: 3,
        meals: 4,
      );
      expect(r.biomassKg, 200);
      expect(r.dailyKg, 6);
      expect(r.perMealKg, 1.5);
      expect(
        FeedingCalculation(
          animals: 1000,
          averageGrams: 200,
          dailyPercent: 0,
          meals: 4,
        ).dailyKg,
        0,
      );
      for (final percent in [-1.0, 101.0, double.nan, double.infinity]) {
        expect(
          () => FeedingCalculation(
            animals: 1000,
            averageGrams: 200,
            dailyPercent: percent,
            meals: 4,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => FeedingCalculation(
          animals: 1000,
          averageGrams: 200,
          dailyPercent: 3,
          meals: 0,
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'Tilapia accepts decimal comma and invalidates previous results',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: FeedingPanel())),
        ),
      );
      for (final (i, value) in ['1000', '200', '3,0', '4'].indexed) {
        await tester.enterText(find.byKey(ValueKey('feeding-input-$i')), value);
      }
      await tester.ensureVisible(find.text('Calcular ración'));
      await tester.tap(find.text('Calcular ración'));
      await tester.pump();
      expect(find.text('Alimento diario calculado: 6.000 kg'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('feeding-input-0')),
        '900',
      );
      await tester.pump();
      expect(find.textContaining('Alimento diario calculado:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Species tools disappear when calculator access is revoked', (
    tester,
  ) async {
    Widget app(ClinicMembership currentMember) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProductionMenu(member: currentMember, onNavigate: (_) {}),
        ),
      ),
    );
    await tester.pumpWidget(app(admin));
    await tester.tap(find.text('Peces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tilapia'));
    await tester.pumpAndSettle();
    expect(find.byType(FeedingPanel), findsOneWidget);
    await tester.pumpWidget(app(member));
    await tester.pumpAndSettle();
    expect(find.byType(FeedingPanel), findsNothing);
    await tester.tap(find.text('Volver a especies'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Porcinos'));
    await tester.tap(find.text('Porcinos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crecimiento y engorda'));
    await tester.pumpAndSettle();
    expect(find.byType(GrowthPanel), findsNothing);
    await tester.pumpWidget(app(admin));
    await tester.pumpAndSettle();
    expect(find.byType(GrowthPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
