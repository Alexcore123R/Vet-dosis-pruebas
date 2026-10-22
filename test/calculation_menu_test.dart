import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/section_menu.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';

void main() {
  testWidgets('Calculation menu separates dose and clinical tools', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository();
    final model = CoreViewModel(repository, await repository.load());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: model,
            builder: (context, _) => model.screen == 'Inicio'
                ? CalculationMenu(onNavigate: model.navigate)
                : Text(model.screen),
          ),
        ),
      ),
    );
    expect(find.text('Calcular dosis de un producto'), findsOneWidget);
    expect(find.text('Otras operaciones de dosis'), findsOneWidget);
    expect(find.text('Cálculos clínicos'), findsOneWidget);
    await tester.tap(find.text('Otras operaciones de dosis'));
    await tester.pumpAndSettle();
    expect(find.text('Operaciones de dosis'), findsOneWidget);
  });
}
