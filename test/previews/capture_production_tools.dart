import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/home_pilot.dart';
import 'package:vetdosis_pro/modules/production/presentation/feeding_panel.dart';
import 'package:vetdosis_pro/modules/production/presentation/growth_panel.dart';

void main() {
  for (final dark in [false, true]) {
    for (final growth in [false, true]) {
      testWidgets('Production ${growth ? 'growth' : 'feeding'} dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader(
          'Roboto',
        )..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'))).load();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: homePilotTheme(
                ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
              ),
              home: Scaffold(
                appBar: AppBar(
                  title: Text(growth ? 'Porcinos · DEMO' : 'Tilapia · DEMO'),
                ),
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: growth
                        ? const GrowthPanel(showCosts: true)
                        : const FeedingPanel(),
                  ),
                ),
              ),
            ),
          ),
        );
        final values = growth
            ? ['10', '100', '120', '856', '2320', '6032']
            : ['1000', '200', '3', '4'];
        for (final (i, value) in values.indexed) {
          await tester.enterText(
            find.byKey(ValueKey('${growth ? 'growth' : 'feeding'}-input-$i')),
            value,
          );
        }
        if (growth) {
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pump();
        }
        final action = find.text(
          growth ? 'Calcular indicadores' : 'Calcular ración',
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(TextField).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'review/production-tools-20261019/${growth ? 'porcinos' : 'tilapia'}-${dark ? 'dark' : 'light'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
