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
import '../agenda_permission_test.dart' show PermissionAgendaFake;

void main() {
  for (final view in ['light', 'dark']) {
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
        AppSettings(visualStyle: 'neu', brightness: view),
      );
      core.navigate('Agenda');
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: VetDosisApp(
            model: core,
            auth: auth,
            operations: PermissionAgendaFake()
              ..response['appointments'] = [
                for (final entry in {
                  'Rocky · DEMO': 'agendado',
                  'Luna · DEMO': 'en_atencion',
                  'Michi · DEMO': 'listo',
                }.entries)
                  {
                    'id': entry.key,
                    'patient_id': null,
                    'patient_name': entry.key,
                    'kind': 'consulta',
                    'state': entry.value,
                    'version': 1,
                    'starts_at': DateTime(2026, 10, 18, 10).toIso8601String(),
                    'ends_at': DateTime(2026, 10, 18, 11).toIso8601String(),
                  },
              ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('review/agenda-pilot-20261018/$view.png');
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
