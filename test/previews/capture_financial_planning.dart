import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import '../support/fake_auth.dart';

void main() {
  for (final view in ['entrada', 'resultado']) {
    testWidgets('Capture section $view with synthetic account', (tester) async {
      tester.view.physicalSize = const Size(390, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final repo = FakeAuth()
        ..rows = [
          const ClinicMembership(
            clinicId: 'demo',
            clinicName: 'DEMO · Cuenta ficticia',
            userId: 'user-a',
            role: ClinicRole.admin,
          ),
        ];
      final auth = AuthViewModel(repo);
      await auth.start();
      final core = CoreViewModel(
        SettingsRepository(),
        AppSettings(visualStyle: 'neu'),
      );
      core.navigate('Planeación financiera');
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: VetDosisApp(model: core, auth: auth),
        ),
      );
      await tester.pumpAndSettle();
      if (view == 'resultado') {
        final values = [
          '50000',
          '20000',
          '10000',
          '5000',
          '100000',
          '33500',
          '1500',
        ];
        for (var i = 0; i < values.length; i++) {
          await tester.enterText(find.byType(TextFormField).at(i), values[i]);
        }
        await tester.ensureVisible(find.text('Calcular escenario'));
        await tester.tap(find.text('Calcular escenario'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.textContaining('Estimaciones antes de impuestos'),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('review/financial-planning-20261018/$view.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      core.dispose();
      auth.dispose();
      await repo.controller.close();
    });
  }
}
