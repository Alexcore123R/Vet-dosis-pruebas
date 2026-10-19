import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/operations/domain/operations_repository.dart';
import 'package:vetdosis_pro/modules/inventory/domain/inventory_repository.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/dashboard_view_model.dart';

class Agenda extends OperationsRepository {
  String? clinic;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async {
    this.clinic = clinic;
    return {'appointments': []};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BrokenStock implements InventoryRepository {
  int calls = 0;
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    calls++;
    throw StateError('offline');
  }

  @override
  Future<void> photo(String a, String b, int c, Uint8List d, String e) async {}
  @override
  Future<String> photoUrl(String path) async => '';
  @override
  Future<dynamic> write(String command, Map<String, dynamic> args) async =>
      null;
}

ClinicMembership member(ClinicRole role) => ClinicMembership(
  clinicId: 'clinic-A',
  clinicName: 'Clínica A',
  userId: 'user-A',
  role: role,
);
HospitalTask task(
  String id,
  String at, {
  HospitalTaskState state = HospitalTaskState.pending,
  String kind = 'medicacion',
  String? snooze,
}) => HospitalTask(
  id: id,
  stayId: 'stay',
  kind: kind,
  label: 'Tratamiento',
  instructions: '',
  dueAt: DateTime.parse(at),
  escalationMinutes: 15,
  state: state,
  version: 1,
  snoozedUntil: snooze == null ? null : DateTime.parse(snooze),
);
void main() {
  test(
    'Partial failure preserves agenda and never invents zero stock',
    () async {
      final agenda = Agenda();
      final stock = BrokenStock();
      final model = DashboardViewModel(
        member: member(ClinicRole.admin),
        operations: agenda,
        inventory: stock,
      );
      await model.load();
      expect(agenda.clinic, 'clinic-A');
      expect(model.agenda, isNotNull);
      expect(model.stock, isNull);
      expect(model.errors.keys, ['Inventario']);
      await model.load(offline: true);
      expect(model.agenda, isNull);
      expect(stock.calls, 1);
      model.dispose();
    },
  );
  test(
    'Inventory access is decided by the server, not the visual job',
    () async {
      final stock = BrokenStock();
      final model = DashboardViewModel(
        member: member(ClinicRole.estilista),
        inventory: stock,
      );
      await model.load();
      expect(stock.calls, 1);
      expect(model.stock, isNull);
      expect(model.errors, contains('Inventario'));
      model.dispose();
    },
  );
  test(
    'Agenda filters cancelled and completed future visits, sorts recent',
    () {
      final model = DashboardViewModel(
        member: member(ClinicRole.admin),
        now: () => DateTime.parse('2026-10-14T12:00:00Z'),
      );
      model.agenda = {
        'appointments': [
          {
            'patient_name': 'later',
            'starts_at': '2026-10-14T15:00:00Z',
            'state': 'agendado',
          },
          {
            'patient_name': 'cancelled',
            'starts_at': '2026-10-14T13:00:00Z',
            'state': 'cancelado',
          },
          {
            'patient_name': 'next',
            'starts_at': '2026-10-14T14:00:00Z',
            'state': 'agendado',
          },
          {
            'patient_name': 'yesterday',
            'starts_at': '2026-10-13T11:00:00Z',
            'state': 'entregado',
          },
          {
            'patient_name': 'today',
            'starts_at': '2026-10-14T11:00:00Z',
            'state': 'en_atencion',
          },
        ],
      };
      expect(model.upcoming.map((a) => a['patient_name']), ['next', 'later']);
      expect(model.recent.map((a) => a['patient_name']), [
        'today',
        'yesterday',
      ]);
      model.dispose();
    },
  );
  test(
    'Upcoming medication respects snooze, excludes completed and non-medication',
    () {
      final model = DashboardViewModel(
        member: member(ClinicRole.admin),
        now: () => DateTime.parse('2026-10-14T12:00:00Z'),
      );
      model.ward = HospitalSnapshot([], [
        task('due', '2026-10-14T11:00:00Z'),
        task('snoozed', '2026-10-14T11:00:00Z', snooze: '2026-10-14T13:00:00Z'),
        task('next', '2026-10-14T14:00:00Z'),
        task('done', '2026-10-14T11:00:00Z', state: HospitalTaskState.done),
        task('observation', '2026-10-14T11:00:00Z', kind: 'revision'),
      ]);
      expect(model.overdue.map((t) => t.id), ['due']);
      expect(model.nextDoses.map((t) => t.id), ['snoozed', 'next']);
      model.dispose();
    },
  );
  testWidgets(
    'Mobile dashboard, grouped calculations, settings and floating navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();
      final model = CoreViewModel(repository, await repository.load());
      await tester.pumpWidget(VetDosisApp(model: model));
      await tester.pumpAndSettle();
      expect(find.text('Resumen de tu espacio'), findsOneWidget);
      expect(find.text('Resumen no disponible.'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Cálculos'),
        ),
        findsNothing,
      );
      expect(find.text('Planes'), findsNothing);
      expect(find.text('Estadísticas y respaldo'), findsNothing);
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Cálculos'));
      await tester.pumpAndSettle();
      expect(find.text('Cálculos clínicos').last, findsOneWidget);
      await tester.tap(find.text('Cálculos clínicos').last);
      await tester.pumpAndSettle();
      expect(model.screen, 'Cálculos clínicos');
      await tester.tap(find.byTooltip('Asistente IA'));
      await tester.pumpAndSettle();
      expect(model.screen, 'Asistente IA');
      await tester.tap(find.byTooltip('Ayuda y soporte'));
      await tester.pumpAndSettle();
      expect(model.screen, 'Ayuda y soporte');
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Plan y pagos de VetDosis'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Plan y pagos de VetDosis'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Exportación y respaldo'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Exportación y respaldo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
