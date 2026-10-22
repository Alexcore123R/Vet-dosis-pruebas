import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/doses/presentation/dose_math_tools.dart';

void main() {
  testWidgets('Dose math tool supports rule of three with explicit inputs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DoseMathTools())),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<DoseMathMode>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regla de tres por peso').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('baselineVolume')), '5');
    await tester.enterText(find.byKey(const ValueKey('baselineWeight')), '50');
    await tester.enterText(find.byKey(const ValueKey('weight')), '120');
    await tester.ensureVisible(find.text('Calcular'));
    await tester.tap(find.text('Calcular'));
    await tester.pumpAndSettle();
    expect(find.text('12 mL'), findsOneWidget);
  });

  testWidgets('Reconstitution calculation uses supplied final volume and UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DoseMathTools())),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<DoseMathMode>).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Unidades internacionales tras reconstitución').last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('totalUnits')), '9000000');
    await tester.enterText(find.byKey(const ValueKey('finalVolume')), '10');
    await tester.enterText(find.byKey(const ValueKey('weight')), '200');
    await tester.enterText(find.byKey(const ValueKey('unitsPerKg')), '5000');
    await tester.ensureVisible(find.text('Calcular'));
    await tester.tap(find.text('Calcular'));
    await tester.pumpAndSettle();
    expect(find.textContaining('mL'), findsWidgets);
    expect(find.textContaining('9000000 UI ÷ 10 mL'), findsOneWidget);
  });
}
