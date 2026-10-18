import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/vet_ui.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Kit supports narrow layouts, large text and $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = brightness == Brightness.light
          ? VetTheme.light()
          : ThemeData(brightness: Brightness.dark, useMaterial3: true);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: VetCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      VetActionButton(
                        label: 'Agendar cita',
                        icon: Icons.add,
                        onPressed: () => taps++,
                      ),
                      const VetActionButton(
                        label: 'Sin permiso',
                        onPressed: null,
                      ),
                      VetActionButton(
                        label: 'Guardando',
                        loading: true,
                        onPressed: () => taps++,
                      ),
                      ListTile(
                        title: const Text('Acceso de prueba'),
                        onTap: () => taps++,
                      ),
                      const VetStatusBadge(
                        label: 'Referencia sin verificar',
                        kind: VetBadgeKind.unverified,
                      ),
                      const VetKpiCard(
                        label: 'Sin registros',
                        value: '—',
                        icon: Icons.calendar_month,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Agendar cita'));
      expect(taps, 1);
      await tester.tap(find.text('Acceso de prueba'));
      expect(taps, 2);
      for (final label in ['Sin permiso', 'Guardando']) {
        final button = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(FilledButton),
          ),
        );
        expect(button.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
