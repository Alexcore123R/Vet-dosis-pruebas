import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/domain/module_access.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/dashboard_screen.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/dashboard_view_model.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/home_pilot.dart';
import 'dashboard_test.dart' show Agenda, member;

class PilotAgenda extends Agenda {
  int reads = 0;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async {
    reads++;
    return {
      'appointments': [
        {
          'patient_name': 'Caso sintético',
          'starts_at': '2030-01-07T12:00:00Z',
          'state': 'agendado',
        },
        {
          'patient_name': 'Caso sintético',
          'starts_at': '2030-01-08T13:00:00Z',
          'state': 'agendado',
        },
        {
          'patient_name': 'Caso cancelado',
          'starts_at': '2030-01-08T13:00:00Z',
          'state': 'cancelado',
        },
        {
          'patient_name': 'Caso antiguo',
          'starts_at': '2029-01-08T13:00:00Z',
          'state': 'agendado',
        },
      ],
    };
  }
}

Future<void> showDashboard(
  WidgetTester tester,
  DashboardViewModel model,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardScreen(
            model: model,
            homePilot: true,
            onNavigate: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Denied summaries never read or display private pilot activity', (
    tester,
  ) async {
    final agenda = PilotAgenda();
    await showDashboard(
      tester,
      DashboardViewModel(
        member: member(ClinicRole.admin),
        operations: agenda,
        moduleAccess: ModuleAccess.denied,
      ),
    );
    final summary = tester.widget<HomeSummary>(find.byType(HomeSummary));
    expect(agenda.reads, 0);
    expect(summary.metrics, isEmpty);
    expect(summary.activity, isNull);
    expect(find.text('Caso sintético'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Chart counts consulted dates, excluding cancelled and older appointments',
    (tester) async {
      final agenda = PilotAgenda();
      await showDashboard(
        tester,
        DashboardViewModel(
          member: member(ClinicRole.auxiliar),
          operations: agenda,
          now: () => DateTime.utc(2030, 1, 8, 12),
        ),
      );
      final summary = tester.widget<HomeSummary>(find.byType(HomeSummary));
      expect(summary.activity!.map((e) => e.$2).reduce((a, b) => a + b), 2);
      expect(summary.activity!.last.$2, 1);
      expect(
        summary.metrics.firstWhere((e) => e.$1 == 'Citas por venir').$2,
        '1',
      );
      expect(summary.metrics.firstWhere((e) => e.$1 == 'Pacientes').$2, '—');
      expect(find.text('Citas consultadas · últimos 7 días'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Pilot fits 320px with 200% text and keeps all practice callbacks in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ClinicalBranch? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: homePilotTheme(ThemeData(brightness: brightness)),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      HomePracticeSelector(
                        selected: ClinicalBranch.small,
                        onChanged: (branch) => selected = branch,
                      ),
                      HomeModuleGrid(
                        actions: const [('Hospitalización', 'Hospitalización')],
                        onNavigate: (_) {},
                      ),
                      const HomeSummary(
                        metrics: [('Hospitalizados', '—', Icons.pets)],
                        activity: [('Lun', 2), ('Mar', 0)],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final (label, branch) in [
          ('Pequeñas especies', ClinicalBranch.small),
          ('Exóticos', ClinicalBranch.exotic),
          ('Producción y grandes especies', ClinicalBranch.production),
          ('Gestión clínica', ClinicalBranch.management),
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          expect(selected, branch);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Pilot theme covers Inicio and Agenda while preserving other appearance',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final core = CoreViewModel(SettingsRepository(), AppSettings(palette: 1));
      final app = VetDosisApp(model: core);
      final original = app.theme(Brightness.light).colorScheme.primary;
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.byType(HomePracticeSelector), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byTooltip('Ajustes'))).colorScheme.primary,
        isNot(original),
      );
      core.navigate('Agenda');
      await tester.pumpAndSettle();
      expect(find.byType(HomePracticeSelector), findsNothing);
      expect(
        Theme.of(tester.element(find.byTooltip('Ajustes'))).colorScheme.primary,
        isNot(original),
      );
      core.navigate('Ajustes');
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byTooltip('Ajustes'))).colorScheme.primary,
        original,
      );
      expect(core.settings.palette, 1);
      await tester.pumpWidget(const SizedBox());
      core.dispose();
    },
  );
}
