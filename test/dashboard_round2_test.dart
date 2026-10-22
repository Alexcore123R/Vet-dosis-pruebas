import 'package:flutter/material.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/dashboard_view_model.dart';
import 'package:vetdosis_pro/modules/hospital/application/hospital_alerts.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'dashboard_test.dart' show member;
import 'hospital_test.dart' as h;
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';

class FixedDashboard extends DashboardViewModel {
  FixedDashboard(ClinicRole role) : super(member: member(role));
  @override
  Future<void> load({bool offline = false}) async {}
}

void main() {
  testWidgets(
    'Financial dashboard honors role and compact access replaces large cards',
    (tester) async {
      final model = FixedDashboard(ClinicRole.auxiliar);
      model.stock = {
        'products': [],
        'shifts': [],
        'day_totals': {
          'gross': '123.45',
          'margin': '20.00',
          'recorded_net': '20.00',
          'cash': '100.00',
          'card': '23.45',
          'transfer': '0.00',
        },
      };
      model.agenda = {'appointments': [], 'tasks': [], 'messages': [],
        'sections': {'tasks': true, 'messages': true}};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardScreen(model: model, onNavigate: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Valor a costo'), findsNothing);
      expect(find.text('Ventas de hoy'), findsNothing);
      expect(find.text('Abrir caja'), findsOneWidget);
      expect(find.text('Tareas de hoy'), findsOneWidget);
      expect(find.text('Anuncios y avisos'), findsOneWidget);
      expect(find.text('Abrir conversación y herramientas'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('Upcoming four appointments use clinic calendar day, not UTC day', () {
    final m = DashboardViewModel(
      member: member(ClinicRole.admin),
      now: () => DateTime.parse('2026-10-14T05:00:00Z'),
    );
    m.stock = {'timezone': 'America/Mexico_City'};
    m.agenda = {
      'appointments': [
        for (final minute in [10, 15, 20, 25, 30])
          {
            'patient_name': '$minute',
            'starts_at': '2026-10-14T05:$minute:00Z',
            'state': 'agendado',
          },
        {
          'patient_name': 'tomorrow',
          'starts_at': '2026-10-14T06:05:00Z',
          'state': 'agendado',
        },
        {
          'patient_name': 'cancelled',
          'starts_at': '2026-10-14T05:01:00Z',
          'state': 'cancelado',
        },
      ],
    };
    expect(m.todayAppointments.map((a) => a['patient_name']), [
      '10',
      '15',
      '20',
      '25',
    ]);
    expect(m.localTime(m.now()).day, 13);
    m.dispose();
  });
  test('Inventory groups different units and uses non-expired lot costs', () {
    final m = DashboardViewModel(member: member(ClinicRole.admin));
    m.stock = {
      'products': [
        {
          'active': true,
          'stock_unit': 'frasco',
          'm8_kind': 'producto',
          'available_stock': '2',
          'precio_venta': '20.00',
          'lots': [
            {
              'cantidad': '2',
              'costo_unitario': '10.00',
              'caducidad': null,
              'expired': false,
            },
            {
              'cantidad': '4',
              'costo_unitario': '10.00',
              'caducidad': '2020-01-01',
              'expired': true,
            },
          ],
        },
        {
          'active': true,
          'stock_unit': 'tableta',
          'm8_kind': 'producto',
          'available_stock': '3',
          'precio_venta': '5.00',
          'lots': [
            {
              'cantidad': '3',
              'costo_unitario': '2.00',
              'caducidad': null,
              'expired': false,
            },
          ],
        },
        {
          'active': false,
          'stock_unit': 'frasco',
          'available_stock': '100',
          'precio_venta': '100.00',
        },
      ],
    };
    expect(m.stockByUnit!['frasco']!.display(), '2');
    expect(m.stockByUnit!['tableta']!.display(), '3');
    expect(m.valueAtCost!.decimal, '26.00');
    expect(m.valueAtSale!.decimal, '55.00');
    expect(m.potentialMargin!.decimal, '29.00');
    (m.stock!['products'] as List).first.remove('available_stock');
    expect(m.stockByUnit, isNull);
    expect(m.valueAtSale, isNull);
    m.dispose();
  });
  test(
    'Tasks exclude completed, notices preserve latest authors and cash is own turn',
    () {
      final m = DashboardViewModel(member: member(ClinicRole.admin));
      m.agenda = {
        'tasks': [
          {'id': 'pending', 'completed_at': null},
          {'id': 'done', 'completed_at': '2026-10-14'},
        ],
        'messages': [
          for (var i = 0; i < 6; i++) {'id': i, 'author_id': 'author-$i'},
        ],
      };
      m.stock = {
        'shifts': [
          {'id': 'other', 'cashier_id': 'other', 'closed_at': null},
          {'id': 'mine', 'cashier_id': 'user-A', 'closed_at': null},
          {
            'id': 'closed',
            'cashier_id': 'user-A',
            'closed_at': '2026-10-14T12:00:00Z',
          },
        ],
      };
      expect(m.pendingTasks.single['id'], 'pending');
      expect(m.messages.map((x) => x['id']), [5, 4, 3, 2]);
      expect(m.messages.first['author_id'], 'author-5');
      expect(m.ownShift!['id'], 'mine');
      expect(m.recentCuts.single['id'], 'closed');
      m.dispose();
    },
  );
  test(
    'Advance warning is distinct, respects snooze and excludes completed',
    () {
      final now = h.noon;
      final jobs = planHospitalAlarms(
        [h.task(due: now.add(const Duration(minutes: 20)))],
        now,
        leadMinutes: 10,
      );
      expect(
        jobs.where((j) => j.advance).single.at,
        now.add(const Duration(minutes: 10)),
      );
      final snoozed = planHospitalAlarms(
        [
          h.task(
            due: now.add(const Duration(minutes: 20)),
            snooze: now.add(const Duration(minutes: 40)),
          ),
        ],
        now,
        leadMinutes: 15,
      );
      expect(
        snoozed.where((j) => j.advance).single.at,
        now.add(const Duration(minutes: 25)),
      );
      expect(
        planHospitalAlarms(
          [h.task(state: HospitalTaskState.done)],
          now,
          leadMinutes: 30,
        ),
        isEmpty,
      );
    },
  );
  test(
    'Preferences persist and changed settings reschedule without duplicate IDs',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final backend = h.FakeAlarms();
      final alerts = HospitalAlerts(backend, prefs, now: () => h.noon);
      await alerts.bind('a:user-a');
      await alerts.initialize();
      await alerts.enable();
      await alerts.updateOptions(leadMinutes: 10, stockWarnings: false);
      final tasks = [h.task(due: h.noon.add(const Duration(minutes: 20)))];
      await alerts.reconcile('a:user-a', tasks);
      expect(backend.scheduled.values.where((j) => j.advance), hasLength(1));
      final ids = backend.scheduled.keys.toSet();
      final writes = backend.writes;
      await alerts.updateOptions(sound: false, vibration: false);
      await alerts.reconcile('a:user-a', tasks);
      expect(backend.scheduled.keys.toSet(), ids);
      expect(backend.writes, greaterThan(writes));
      final restored = HospitalAlerts(h.FakeAlarms(), prefs);
      expect(restored.sound, isFalse);
      expect(restored.vibration, isFalse);
      expect(restored.stockWarnings, isFalse);
      expect(restored.leadMinutes, 10);
      await expectLater(
        alerts.updateOptions(leadMinutes: 7),
        throwsFormatException,
      );
      alerts.dispose();
      restored.dispose();
    },
  );
}
