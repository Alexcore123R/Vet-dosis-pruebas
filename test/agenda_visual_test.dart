import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'support/fake_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_screen.dart';
import 'package:vetdosis_pro/modules/operations/presentation/appointment_summary.dart';
import 'package:vetdosis_pro/vet_ui.dart';
import 'agenda_permission_test.dart' show PermissionAgendaFake;

void main() {
  test('appointment kinds have clear Spanish display labels', () {
    expect(appointmentKindLabel('estetica'), 'Estética / baño / peluquería');
    expect(appointmentKindLabel('cirugia'), 'Cirugía');
    expect(appointmentKindLabel('hospital_visita'), 'Visita de hospitalizado');
  });
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
        expect(find.text('Agenda y citas'), findsNWidgets(2));
        expect(find.widgetWithText(ChoiceChip, 'Agenda y citas'), findsOneWidget);
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
  testWidgets('Status and date filters compose without changing appointments', (
    tester,
  ) async {
    final fake = PermissionAgendaFake();
    final today = DateTime.now();
    Map<String, dynamic> row(String id, String state, DateTime date) => {
      'id': id,
      'patient_name': id,
      'kind': 'consulta',
      'patient_id': null,
      'starts_at': date.toIso8601String(),
      'ends_at': date.add(const Duration(hours: 1)).toIso8601String(),
      'state': state,
      'version': 1,
    };
    fake.response['appointments'] = [
      row('Hoy agendada', 'agendado', today),
      row('Hoy atención', 'en_atencion', today),
      row('Mañana atención', 'en_atencion', today.add(const Duration(days: 1))),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OperationsScreen(
              repository: fake,
              member: const ClinicMembership(
                clinicId: 'c1',
                clinicName: 'Demo',
                userId: 'u1',
                role: ClinicRole.admin,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 citas para hoy · 3 citas cargadas'), findsOneWidget);
    await tester.ensureVisible(find.text('En atención (2)'));
    await tester.tap(find.text('En atención (2)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hoy agendada · Consulta'), findsNothing);
    expect(find.textContaining('Hoy atención · Consulta'), findsOneWidget);
    expect(find.textContaining('Mañana atención · Consulta'), findsOneWidget);
    await tester.ensureVisible(find.text('Calendario'));
    await tester.tap(find.text('Calendario'));
    await tester.pumpAndSettle();
    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(today);
    await tester.pumpAndSettle();
    expect(find.textContaining('Mañana atención · Consulta'), findsNothing);
    await tester.ensureVisible(find.text('Canceladas (0)'));
    await tester.tap(find.text('Canceladas (0)'));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay citas con ese estado para la selección actual.'),
      findsOneWidget,
    );
    expect((fake.response['appointments'] as List).length, 3);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Authenticated home and agenda headers fit compact large-text screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final repo = FakeAuth();
      final auth = AuthViewModel(repo);
      await auth.start();
      final core = CoreViewModel(SettingsRepository(), const AppSettings());
      for (final page in ['Inicio', 'Agenda']) {
        core.navigate(page);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: CoreShell(
              model: core,
              auth: auth,
              operations: PermissionAgendaFake(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page);
      }
      await tester.pumpWidget(const SizedBox());
      core.dispose();
      auth.dispose();
      await repo.controller.close();
    },
  );
}
