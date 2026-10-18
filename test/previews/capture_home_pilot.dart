// Preview fixtures only: all account, clinic and activity data are synthetic.
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
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import '../support/fake_auth.dart';
import '../patients_test.dart' show FakePatients;
import '../hospital_test.dart' show FakeHospital;
import '../remaining_test.dart' show FakeOperations;

class PreviewOperations extends FakeOperations {
  PreviewOperations(this.empty);
  final bool empty;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async {
    final now = DateTime.now();
    return {
      'appointments': [
        if (!empty)
          for (var i = 0; i < 5; i++)
            {
              'patient_name': 'Caso ficticio ${i + 1}',
              'kind': 'consulta',
              'state': 'agendado',
              'starts_at':
                  (i == 0
                          ? now.add(const Duration(hours: 1))
                          : now.subtract(Duration(days: i)))
                      .toUtc()
                      .toIso8601String(),
            },
      ],
      'tasks': [
        if (!empty)
          {'title': 'Pendiente de demostración', 'completed_at': null},
      ],
      'members': [],
    };
  }
}

class PreviewPatients extends FakePatients {
  PreviewPatients(this.empty);
  final bool empty;
  @override
  Future<List<VetPatient>> patients(String clinic) async =>
      empty ? [] : super.patients(clinic);
}

void main() {
  for (final dark in [false, true]) {
    for (final empty in [false, true]) {
      testWidgets('Home preview dark=$dark empty=$empty', (tester) async {
        tester.view.physicalSize = const Size(390, 1400);
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
        final repo = FakeAuth();
        repo.rows = [
          const ClinicMembership(
            clinicId: 'a',
            userId: 'user-a',
            role: ClinicRole.auxiliar,
            clinicName: 'DEMO · Datos ficticios',
          ),
        ];
        final auth = AuthViewModel(repo);
        await auth.start();
        final core = CoreViewModel(
          SettingsRepository(),
          AppSettings(visualStyle: 'neu', brightness: dark ? 'dark' : 'light'),
        );
        final hospital = FakeHospital();
        if (empty) hospital.snapshot = const HospitalSnapshot([], []);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: VetDosisApp(
              model: core,
              auth: auth,
              operations: PreviewOperations(empty),
              patients: PreviewPatients(empty),
              hospital: hospital,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/brand/vetdosis-logo.png'),
            key.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'review/home-pilot-20261018/inicio-${empty ? 'empty' : 'demo'}-${dark ? 'dark' : 'light'}.png',
          );
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
}
