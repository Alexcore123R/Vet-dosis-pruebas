import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_screen.dart';
import 'package:vetdosis_pro/vet_ui.dart';
import 'agenda_permission_test.dart' show PermissionAgendaFake;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Agenda keeps read-only actions and empty state in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final core = CoreViewModel(
          SettingsRepository(),
          AppSettings(visualStyle: 'neu'),
        );
        final fake = PermissionAgendaFake();
        fake.response['appointments'] = <Map<String, dynamic>>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: VetDosisApp(model: core).theme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: OperationsScreen(
                    repository: fake,
                    member: const ClinicMembership(
                      clinicId: 'c1',
                      clinicName: 'Espacio de prueba',
                      userId: 'u1',
                      role: ClinicRole.admin,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Agenda y citas'), findsOneWidget);
        expect(find.text('No hay citas registradas.'), findsOneWidget);
        expect(find.byType(VetCard), findsWidgets);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Agendar cita'),
        );
        expect(button.onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        core.dispose();
      },
    );
  }
}
