import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'support/fake_auth.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_NEU');
  setUpAll(() async {
    if (capture) {
      final font = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      await font.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final mode in ['light', 'dark']) {
    testWidgets('Access remains usable on a small screen in $mode', (
      tester,
    ) async {
      if (capture) debugDisableShadows = false;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final core = CoreViewModel(
        SettingsRepository(),
        AppSettings(brightness: mode),
      );
      final repo = FakeAuth()..userId = null;
      final auth = AuthViewModel(repo);
      await auth.start();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: VetDosisApp(model: core, auth: auth, requireAuth: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/brand/vetdosis-logo.png'),
          tester.element(find.byType(Image).first),
        );
      });
      await tester.pumpAndSettle();
      if (capture) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('review/neu-20261023/login-$mode.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      debugDisableShadows = true;
      await tester.scrollUntilVisible(
        find.byTooltip('Mostrar contraseña'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Iniciar sesión'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(auth.signedIn, isFalse);
      expect(find.text('Ingresa un correo válido'), findsOneWidget);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      core.dispose();
      await repo.controller.close();
    });
  }
  testWidgets('Bottom menu respects role and Más opens the complete drawer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeAuth(); // Auxiliary: cannot access clinical calculations.
    final auth = AuthViewModel(repo);
    await auth.start();
    final core = CoreViewModel(SettingsRepository(), const AppSettings());
    await tester.pumpWidget(VetDosisApp(model: core, auth: auth));
    await tester.pumpAndSettle();
    final nav = find.byType(NavigationBar);
    expect(
      find.descendant(of: nav, matching: find.text('Cálculos')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(of: nav, matching: find.text('Pacientes')),
    );
    await tester.pumpAndSettle();
    expect(core.screen, 'Pacientes');
    await tester.tap(find.descendant(of: nav, matching: find.text('Más')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    core.dispose();
    await repo.controller.close();
  });
}
