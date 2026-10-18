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
import '../patients_visual_test.dart' show CatalogPatients;
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patient_catalog.dart';

PatientEvent event(EventKind kind, {required Map<String, dynamic> data}) =>
    PatientEvent(
      id: '${kind.name}-${data['date']}',
      kind: kind,
      data: data,
      createdAt: DateTime.parse('${data['date']}T12:00:00Z'),
      createdBy: 'user-a',
    );

void main() {
  for (final view in [
    'lista-light',
    'lista-dark',
    'ficha-light',
    'ficha-dark',
  ]) {
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
            clinicId: 'a',
            clinicName: 'DEMO · Cuenta ficticia',
            userId: 'user-a',
            role: ClinicRole.admin,
          ),
        ];
      final auth = AuthViewModel(repo);
      await auth.start();
      final core = CoreViewModel(
        SettingsRepository(),
        AppSettings(
          visualStyle: 'neu',
          brightness: view.endsWith('dark') ? 'dark' : 'light',
        ),
      );
      core.navigate('Pacientes');
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: VetDosisApp(
            model: core,
            auth: auth,
            patients: CatalogPatients()
              ..rows = [
                event(
                  EventKind.weight,
                  data: {'date': '2026-10-01', 'kg': '12.5'},
                ),
                event(
                  EventKind.weight,
                  data: {'date': '2026-10-18', 'kg': '12.8'},
                ),
                event(
                  EventKind.allergy,
                  data: {
                    'date': '2026-10-18',
                    'substance': 'Alergia DEMO',
                    'reaction': 'Reacción DEMO',
                    'notes': 'Registro ficticio para revisar la presentación.',
                  },
                ),
              ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (view.startsWith('ficha')) {
        await tester.tap(find.text('Lúna DEMO'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(PatientIdentity));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('review/patients-pilot-20261018/$view.png');
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
