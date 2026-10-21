import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_screen.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_view_model.dart';
import 'remaining_test.dart' show FakeOperations;

class PermissionAgendaFake extends FakeOperations {
  bool failLoad = false, legacy = false;
  Map<String, dynamic> response = {
    'permissions': {
      'appointment.read': true,
      'appointment.manage': false,
      'patient.read': false,
    },
    'sections': {'appointments': true},
    'members': [
      {'user_id': 'u1', 'role': 'member'},
    ],
    'appointments': [
      {
        'id': 'a1',
        'patient_id': 'p1',
        'patient_name': 'Synthetic appointment',
        'kind': 'consulta',
        'starts_at': '2030-01-01T12:00:00Z',
        'ends_at': '2030-01-01T13:00:00Z',
        'state': 'agendado',
        'version': 1,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async {
    if (failLoad) throw StateError('denied');
    return legacy ? {'appointments': []} : response;
  }
}

void main() {
  test(
    'A failed or downgraded response cannot restore legacy authority',
    () async {
      final fake = PermissionAgendaFake();
      final model = OperationsViewModel(fake, 'c1');
      await model.load();
      expect(model.allowed('appointment.read'), true);
      expect(model.allowed('appointment.manage'), false);
      fake.failLoad = true;
      await model.load();
      expect(model.explicitPermissions, true);
      expect(model.allowed('appointment.read'), false);
      expect(model.sectionAllowed('appointments'), false);
      fake.failLoad = false;
      fake.legacy = true;
      await model.load();
      expect(model.data, isEmpty);
      expect(model.explicitPermissions, true);
      expect(model.error, isNotNull);
      model.dispose();
    },
  );

  testWidgets(
    'An admin with read permission cannot schedule or open the record',
    (tester) async {
      final fake = PermissionAgendaFake();
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OperationsScreen(
                repository: fake,
                member: const ClinicMembership(
                  clinicId: 'c1',
                  clinicName: 'Synthetic',
                  userId: 'u1',
                  role: ClinicRole.admin,
                ),
                onOpenPatient: (_) async {
                  opened = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Agendar cita'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        false,
      );
      await tester.tap(find.textContaining('Synthetic appointment'));
      await tester.pumpAndSettle();
      expect(opened, false);
      expect(find.text('Desempeño'), findsNothing);
      expect(find.text('Ficha médica privada'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'An unavailable section does not render its old action controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsScreen(
              repository: PermissionAgendaFake(),
              initialSection: 'services',
              member: const ClinicMembership(
                clinicId: 'c1',
                clinicName: 'Synthetic',
                userId: 'u1',
                role: ClinicRole.admin,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Esta sección no está habilitada para tu cuenta.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('service.read o service.manage'),
        findsOneWidget,
      );
      expect(find.text('Nuevo servicio'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('An explicit service grant enables catalog management', (
    tester,
  ) async {
    final fake = PermissionAgendaFake()
      ..response = {
        'permissions': {'service.manage': true},
        'sections': {'services': true},
        'members': [
          {'user_id': 'u1', 'role': 'member'},
        ],
        'people': [
          {'user_id': 'u1', 'display_name': 'Synthetic staff'},
        ],
        'services': [],
      };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OperationsScreen(
              repository: fake,
              initialSection: 'services',
              member: const ClinicMembership(
                clinicId: 'c1',
                clinicName: 'Synthetic',
                userId: 'u1',
                role: ClinicRole.estilista,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nuevo servicio'), findsOneWidget);
    await tester.ensureVisible(find.text('Cirugías'));
    await tester.tap(find.text('Cirugías'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ActionChip, 'Cirugía'));
    await tester.tap(find.widgetWithText(ActionChip, 'Cirugía'));
    await tester.pumpAndSettle();
    final entry = tester.widget<RxEntryScreen>(find.byType(RxEntryScreen));
    expect(entry.initial['category'], 'cirugia');
    expect(entry.initial['name'], 'Cirugía');
    expect(entry.initial.containsKey('price'), false);
    expect(entry.fields.any((field) => field.key == 'name'), true);
    expect(
      entry.fields.any(
        (field) => field.key == 'subcategory' && field.type == 'text',
      ),
      true,
    );

    expect(
      find.text('Esta sección no está habilitada para tu cuenta.'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final permitted in [false, true]) {
    testWidgets(
      'Products and pharmacy navigation respects access: $permitted',
      (tester) async {
        final fake = PermissionAgendaFake()
          ..response = {
            'permissions': {'service.read': true},
            'sections': {'services': true},
            'services': [],
          };
        String? destination;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: OperationsScreen(
                  repository: fake,
                  initialSection: 'services',
                  member: const ClinicMembership(
                    clinicId: 'c1',
                    clinicName: 'Synthetic',
                    userId: 'u1',
                    role: ClinicRole.estilista,
                  ),
                  canOpenInventory: permitted,
                  canOpenSales: permitted,
                  onNavigate: (value) => destination = value,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final inventory = find.widgetWithText(
          OutlinedButton,
          'Productos y farmacia',
        );
        final sales = find.widgetWithText(OutlinedButton, 'Registrar venta');
        expect(
          tester.widget<OutlinedButton>(inventory).onPressed != null,
          permitted,
        );
        expect(
          tester.widget<OutlinedButton>(sales).onPressed != null,
          permitted,
        );
        if (permitted) {
          await tester.ensureVisible(inventory);
          await tester.tap(inventory);
          expect(destination, 'Inventario');
          await tester.ensureVisible(sales);
          await tester.tap(sales);
          expect(destination, 'Caja');
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
