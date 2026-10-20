import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/operations/domain/appointment_care.dart';
import 'package:vetdosis_pro/modules/operations/presentation/appointment_care_panel.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_view_model.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_screen.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'remaining_test.dart' show FakeOperations;

class CareFake extends FakeOperations implements AppointmentCareRepository {
  Completer<Map<String, dynamic>>? pending;
  bool failCare = false;
  Map<String, dynamic> response = {
    'schema_version': 1,
    'clinic_id': 'c',
    'day': '2026-10-20',
    'day_start': '2026-10-20T06:00:00Z',
    'day_end': '2026-10-21T06:00:00Z',
    'appointments': [
      {
        'appointment_id': 'a',
        'records': [],
        'can_manage': true,
        'can_close': false,
      },
    ],
  };
  Map<String, dynamic>? saved;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async => {
    'appointments': [
      {
        'id': 'a',
        'version': 1,
        'patient_id': 'p',
        'patient_name': 'Paciente sintético',
        'kind': 'consulta',
        'state': 'en_atencion',
        'starts_at': '2026-10-20T12:00:00Z',
        'ends_at': '2026-10-20T13:00:00Z',
        'professional_id': 'u',
      },
    ],
    'sections': {'appointments': true},
    'people': [
      {'user_id': 'u', 'display_name': 'Veterinario sintético'},
    ],
    'permissions': {'appointment.read': true},
  };
  @override
  Future<Map<String, dynamic>> careSnapshot(
    String clinic,
    List<String> ids,
  ) async {
    if (failCare) throw StateError('revoked');
    return pending?.future ?? response;
  }

  @override
  Future<void> careWrite(
    String clinic,
    String appointment,
    int version,
    String action,
    Map<String, dynamic> data,
    String operation,
  ) async {
    saved = data;
  }
}

void main() {
  test(
    'Queue uses clinic day and carries only active previous appointments',
    () {
      final start = DateTime.parse('2026-10-20T06:00:00Z');
      final end = DateTime.parse('2026-10-21T06:00:00Z');
      bool included(String at, String state) =>
          inCareQueue({'starts_at': at, 'state': state}, start, end);
      expect(included('2026-10-20T05:59:00Z', 'agendado'), false);
      expect(included('2026-10-20T05:59:00Z', 'en_atencion'), true);
      expect(included('2026-10-19T05:59:00Z', 'listo'), true);
      expect(included('2026-10-20T06:00:00Z', 'agendado'), true);
      expect(included('2026-10-21T06:00:00Z', 'agendado'), false);
      expect(included('2026-10-22T06:00:00Z', 'listo'), false);
      expect(included('2026-10-20T08:00:00Z', 'cancelado'), false);
      expect(included('2026-10-19T08:00:00Z', 'entregado'), false);
    },
  );
  test(
    'Budget acceptance requires reference and delivery requires explicit checks',
    () {
      final intake = {
        'reason': 'Consulta',
        'belongings': 'Ninguna',
        'authorized_services': 'Consulta',
        'authorized_by': 'Tutor',
        'pickup_person': 'Tutor',
      };
      expect(validateCare('admit', intake)['budget_accepted'], false);
      expect(
        () => validateCare('admit', {...intake, 'budget_accepted': true}),
        throwsFormatException,
      );
      expect(
        () => validateCare('deliver', {
          'released_to': 'Tutor',
          'belongings_outcome': 'Ninguna',
        }),
        throwsFormatException,
      );
      expect(
        validateCare('deliver', {
          'released_to': 'Tutor',
          'belongings_outcome': 'Ninguna',
          'pickup_verified': true,
          'instructions_delivered': true,
        })['pickup_verified'],
        true,
      );
      expect(
        () => validateCare('ready', {
          'instructions': 'Test',
          'clinical_date': '2026-02-30',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'Suspended, failed and out-of-scope snapshots never restore care data',
    () async {
      final repo = CareFake();
      final model = OperationsViewModel(repo, 'c');
      await model.load();
      expect(model.care['a'], isNotNull);
      repo.pending = Completer();
      final loading = model.load();
      await Future<void>.delayed(Duration.zero);
      model.suspend();
      repo.pending!.complete(repo.response);
      await loading;
      expect(model.care, isEmpty);
      expect(model.data, isEmpty);
      repo.pending = null;
      repo.failCare = true;
      await model.load();
      expect(model.careError, isNotNull);
      expect(model.care, isEmpty);
      repo.failCare = false;
      repo.response = {...repo.response, 'clinic_id': 'other'};
      await model.load();
      expect(model.careWindow, isNull);
      expect(model.care, isEmpty);
      model.dispose();
    },
  );
  testWidgets(
    'Read-only staff cannot close a consultation or skip delivery steps',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppointmentCarePanel(
              appointment: const {
                'id': 'a',
                'version': 1,
                'patient_name': 'Synthetic',
                'kind': 'consulta',
                'state': 'en_atencion',
              },
              data: const {
                'can_manage': true,
                'can_close': false,
                'records': [],
              },
              repository: CareFake(),
              clinic: 'c',
              onSaved: () async {},
              isCurrent: () => true,
            ),
          ),
        ),
      );
      expect(find.text('Indicaciones y listo'), findsNothing);
      expect(find.text('Registrar entrega'), findsNothing);
      expect(find.textContaining('El cierre de consulta'), findsOneWidget);
    },
  );
  testWidgets('Care cards fit 320px with large text and both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppointmentCarePanel(
                    appointment: const {
                      'id': 'a',
                      'version': 2,
                      'kind': 'consulta',
                      'state': 'listo',
                    },
                    data: const {
                      'can_manage': true,
                      'can_close': true,
                      'records': [
                        {
                          'action': 'admit',
                          'created_at': '2026-10-20T12:00:00Z',
                          'details': {
                            'reason': 'Consulta de prueba',
                            'pickup_person': 'Tutor',
                          },
                        },
                        {
                          'action': 'ready',
                          'created_at': '2026-10-20T13:00:00Z',
                          'clinical_recorded': true,
                          'details': {'clinical_recorded': true},
                        },
                      ],
                    },
                    repository: CareFake(),
                    clinic: 'c',
                    onSaved: () async {},
                    isCurrent: () => true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Registrar entrega'), findsOneWidget);
      expect(
        find.text('Cierre clínico guardado en el expediente.'),
        findsOneWidget,
      );
    }
  });
  testWidgets(
    'Full day card preserves controls at 320px and clears on background',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CareFake();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: OperationsScreen(
                  repository: repo,
                  member: const ClinicMembership(
                    clinicId: 'c',
                    clinicName: 'Synthetic',
                    userId: 'u',
                    role: ClinicRole.mvz,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Paciente sintético'), findsOneWidget);
      expect(
        find.textContaining('Responsable: Veterinario sintético'),
        findsOneWidget,
      );
      expect(find.text('Registrar ingreso'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.textContaining('Paciente sintético'), findsNothing);
      repo.fail = true;
      repo.failCare = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Registrar ingreso'), findsNothing);
    },
  );
  testWidgets(
    'A stale open form cannot save; the checked service submission closes once',
    (tester) async {
      final repo = CareFake();
      var current = true, refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppointmentCarePanel(
              appointment: const {
                'id': 'a',
                'version': 1,
                'patient_name': 'Synthetic',
                'kind': 'estetica',
                'state': 'en_atencion',
              },
              data: const {
                'can_manage': true,
                'can_close': true,
                'records': [],
              },
              repository: repo,
              clinic: 'c',
              onSaved: () async {
                refreshed++;
              },
              isCurrent: () => current,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Indicaciones y listo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Indicaciones sintéticas',
      );
      current = false;
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(repo.saved, isNull);
      expect(refreshed, 0);
      expect(find.textContaining('La vista cambió'), findsOneWidget);
      current = true;
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(repo.saved?['instructions'], 'Indicaciones sintéticas');
      expect(refreshed, 1);
    },
  );
}
