import 'package:vetdosis_pro/modules/auth/domain/staff_labels.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/operations/domain/operations_repository.dart';
import 'package:vetdosis_pro/modules/operations/presentation/appointment_patient_picker.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_screen.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patient_form.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'remaining_test.dart' show FakeOperations;

class AgendaFake extends FakeOperations
    implements AppointmentPatientRepository {
  Completer<List<Map<String, dynamic>>>? pending;
  bool failSearch = false;
  @override
  Future<List<Map<String, dynamic>>> searchPatients(
    String clinic,
    String query,
  ) async {
    if (failSearch) throw StateError('denied');
    return pending?.future ??
        [
          {
            'id': 'p1',
            'name': 'Paciente ficticio',
            'species': 'Especie de prueba',
          },
        ];
  }

  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async => {
    'members': [
      {'user_id': 'u1', 'role': 'mvz'},
    ],
    'appointments': [
      {
        'id': 'a1',
        'patient_id': 'p1',
        'patient_name': 'Paciente ficticio',
        'kind': 'consulta',
        'starts_at': '2030-01-01T12:00:00Z',
        'ends_at': '2030-01-01T13:00:00Z',
        'state': 'agendado',
        'notes': '',
        'version': 1,
      },
    ],
  };
}

const member = ClinicMembership(
  clinicId: 'c1',
  clinicName: 'Clínica ficticia',
  userId: 'u1',
  role: ClinicRole.mvz,
);
void main() {
  test(
    'Staff labels use the clinic display name without exposing professional data',
    () {
      expect(
        staffLabel('user-id', [
          {'user_id': 'user-id', 'display_name': 'Ana'},
        ]),
        'Ana',
      );
      expect(
        staffLabel('12345678-very-long-id', [], role: 'auxiliar'),
        'Auxiliar · 12345678',
      );
    },
  );
  testWidgets(
    'A pending patient save blocks Back and success closes without discard prompt',
    (tester) async {
      final pending = Completer<String?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PatientForm(
                      owners: const [],
                      save: (_, _, _) => pending.future,
                    ),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Paciente prueba');
      await tester.enterText(find.byType(TextField).at(1), 'Especie prueba');
      await tester.scrollUntilVisible(
        find.text('Crear paciente'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Crear paciente'));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(find.text('Nuevo paciente'), findsOneWidget);
      expect(find.text('Cambios sin guardar'), findsNothing);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsOneWidget);
    },
  );

  testWidgets(
    'Changing a patient query rejects a late result and failed lookup hides names',
    (tester) async {
      final repo = AgendaFake()..pending = Completer();
      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentPatientPicker(repository: repo, clinic: 'c1'),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Anterior');
      await tester.tap(find.text('Buscar paciente'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Otra búsqueda');
      repo.pending!.complete([
        {'id': 'private', 'name': 'Resultado anterior', 'species': 'Prueba'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Resultado anterior'), findsNothing);
      repo.pending = null;
      await tester.tap(find.text('Buscar paciente'));
      await tester.pumpAndSettle();
      expect(find.text('Paciente ficticio'), findsOneWidget);
      repo.failSearch = true;
      await tester.tap(find.text('Buscar paciente'));
      await tester.pumpAndSettle();
      expect(find.text('Paciente ficticio'), findsNothing);
    },
  );
  testWidgets(
    'Agenda links a patient without retyping identity and opens the linked record',
    (tester) async {
      String? opened;
      final repo = AgendaFake();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OperationsScreen(
                repository: repo,
                member: member,
                onOpenPatient: (id) async {
                  opened = id;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.textContaining('Vinculado al expediente'),
      );
      await tester.tap(find.textContaining('Vinculado al expediente'));
      expect(opened, 'p1');
      await tester.ensureVisible(find.text('Agendar cita'));
      await tester.tap(find.text('Agendar cita'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Paciente');
      await tester.tap(find.text('Buscar paciente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paciente ficticio'));
      await tester.pumpAndSettle();
      expect(find.text('Cita para Paciente ficticio'), findsOneWidget);
      final form = tester.widget<RxEntryScreen>(find.byType(RxEntryScreen));
      expect(form.initial['patient_id'], 'p1');
      expect(form.fields.any((f) => f.key == 'patient_name'), false);
      await expectLater(
        form.submit({
          ...form.initial,
          'starts_at': '2026-10-12T17:56:00-06:00',
          'ends_at': '2026-10-12T09:31:00-06:00',
        }, 'invalid-time-test'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('posteriores'),
          ),
        ),
      );
    },
  );
  testWidgets('Patient capture can be kept on Back and discarded explicitly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PatientForm(
                    owners: const [],
                    save: (_, _, _) async => null,
                  ),
                ),
              ),
              child: const Text('Abrir captura'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir captura'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Paciente pendiente');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('Paciente pendiente'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir sin guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir captura'), findsOneWidget);
  });
}
