import 'package:vetdosis_pro/modules/patients/presentation/patient_form.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_repository.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patient_view_model.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patients_screen.dart';
import 'package:vetdosis_pro/modules/patients/presentation/event_form.dart';
import 'package:vetdosis_pro/modules/patients/application/voice_dictation.dart';
import 'support/fake_auth.dart';
import 'package:vetdosis_pro/modules/patients/presentation/signature_pad.dart';

const patient = VetPatient(
  id: 'patient-a',
  clinicId: 'a',
  name: 'Paciente ficticio',
  species: 'Especie ficticia',
  breed: '',
  sex: 'sin especificar',
  ownerId: 'owner-a',
);
ClinicMembership membership(ClinicRole role) => ClinicMembership(
  clinicId: 'a',
  clinicName: 'Clínica ficticia',
  userId: 'user-a',
  role: role,
);
PatientEvent event(EventKind kind, {Map<String, dynamic>? data}) =>
    PatientEvent(
      id: kind.name,
      kind: kind,
      data: data ?? {'date': '2026-01-01'},
      createdAt: DateTime.utc(2026),
      createdBy: 'user-a',
    );

class FakePatients implements PatientRepository {
  int ownerReads = 0, eventReads = 0, writes = 0;
  bool fail = false;
  Completer<List<PatientEvent>>? pending;
  List<PatientEvent> rows = [];
  @override
  Future<List<VetPatient>> patients(String clinicId) async {
    if (fail) throw StateError('unavailable');
    return [patient];
  }

  @override
  Future<List<VetOwner>> owners(String clinicId) async {
    ownerReads++;
    return [
      const VetOwner(
        'owner-a',
        'Tutor reservado de prueba',
        '+520000000000',
        '',
        '',
      ),
    ];
  }

  @override
  Future<List<PatientEvent>> events(String clinicId, String patientId) async {
    eventReads++;
    return pending == null ? rows : pending!.future;
  }

  @override
  Future<String> createPatient(
    String clinicId,
    Map<String, dynamic> p,
    Map<String, dynamic>? o,
    String op,
  ) async {
    writes++;
    return 'created';
  }

  @override
  Future<void> addEvent(
    String clinicId,
    String patientId,
    EventKind kind,
    Map<String, dynamic> data,
    String op,
  ) async {
    writes++;
    rows.add(event(kind, data: data));
  }
}

class FakeVoice implements VoiceDictation {
  bool stopped = false;
  @override
  Future<bool> start(
    void Function(String) onText,
    void Function(String) onError,
  ) async {
    onText('Texto ficticio dictado para revisión');
    return true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test(
    'Fechas reales, decimales positivos y prevención sin intervalo inventado',
    () {
      expect(calendarDate('2024-02-29'), '2024-02-29');
      for (final bad in [
        '2025-02-29',
        '2026-13-01',
        '0000-01-01',
        '01/01/2026',
      ]) {
        expect(() => calendarDate(bad), throwsFormatException);
      }
      expect(
        validateEvent(EventKind.weight, {
          'date': '2026-01-01',
          'kg': '1,25',
        })['kg'],
        '1.25',
      );
      expect(
        () =>
            validateEvent(EventKind.weight, {'date': '2026-01-01', 'kg': '0'}),
        throwsFormatException,
      );
      expect(
        () => validateEvent(EventKind.weight, {
          'date': '2026-01-01',
          'kg': 'NaN',
        }),
        throwsFormatException,
      );
      final preventive = validateEvent(EventKind.preventive, {
        'date': '2026-01-01',
        'type': 'vacuna',
        'product': 'Producto ficticio',
      });
      expect(preventive['next_date'], isNull);
      expect(
        () => validateEvent(EventKind.preventive, {
          'date': '2026-02-01',
          'type': 'vacuna',
          'product': 'Ficticio',
          'next_date': '2026-01-01',
        }),
        throwsFormatException,
      );
    },
  );
  test('Consentimiento requiere texto, aceptación y un trazo válido', () {
    final base = <String, dynamic>{
      'date': '2026-01-01',
      'procedure': 'Ficticio',
      'text': 'Texto ficticio sin validez de modelo legal',
      'signer': 'Tutor ficticio',
      'accepted': true,
      'signature': [
        [0.1, 0.2],
        [0.4, 0.5],
        null,
      ],
    };
    expect(validateEvent(EventKind.consent, base)['accepted'], true);
    for (final replacement in [false, null]) {
      expect(
        () => validateEvent(EventKind.consent, {
          ...base,
          'accepted': replacement,
        }),
        throwsFormatException,
      );
    }
    for (final signature in [
      [],
      [
        [0.1, 0.2],
        [0.1, 0.2],
      ],
      [
        [0.1, 0.2],
        [double.nan, 0.5],
      ],
      [
        [0.1, 0.2],
        [1.1, 0.5],
      ],
    ]) {
      expect(
        () =>
            validateEvent(EventKind.consent, {...base, 'signature': signature}),
        throwsFormatException,
      );
    }
  });
  test('SOAP no crea diagnóstico ni plan a partir del subjetivo', () {
    final note = validateEvent(EventKind.soap, {
      'date': '2026-01-01',
      'reason': 'Ficticio',
      'species_template': 'Ficticia',
      'subjective': 'Observación de prueba',
    });
    expect(note['assessment'], '');
    expect(note['plan'], '');
    expect(
      () => validateEvent(EventKind.soap, {
        'date': '2026-01-01',
        'reason': 'Ficticio',
        'species_template': 'Ficticia',
      }),
      throwsFormatException,
    );
  });
  test(
    'Auxiliar no solicita propietarios, no ve firma ni escribe SOAP',
    () async {
      final repo = FakePatients()
        ..rows = [
          event(EventKind.consent),
          event(EventKind.weight, data: {'date': '2026-01-01', 'kg': '1'}),
        ];
      final vm = PatientViewModel(repo, membership(ClinicRole.auxiliar));
      await vm.load();
      await vm.select(patient);
      expect(repo.ownerReads, 0);
      expect(vm.owners, isEmpty);
      expect(vm.events.map((e) => e.kind), [EventKind.weight]);
      expect(await vm.add(EventKind.soap, {}, newOperationId()), false);
      expect(repo.writes, 0);
      vm.dispose();
    },
  );
  test(
    'Recepción no solicita historial clínico; estilista no captura pacientes',
    () async {
      final repo = FakePatients();
      final reception = PatientViewModel(
        repo,
        membership(ClinicRole.recepcion),
      );
      await reception.load();
      await reception.select(patient);
      expect(repo.ownerReads, 1);
      expect(repo.eventReads, 0);
      expect(reception.events, isEmpty);
      reception.dispose();
      final stylist = PatientViewModel(repo, membership(ClinicRole.estilista));
      expect(
        await stylist.create(
          {'name': 'A', 'species': 'B'},
          null,
          newOperationId(),
        ),
        false,
      );
      expect(repo.writes, 0);
      stylist.dispose();
    },
  );
  test('Fallo de lectura elimina contactos y expediente anteriores', () async {
    final repo = FakePatients();
    final vm = PatientViewModel(repo, membership(ClinicRole.admin));
    await vm.load();
    await vm.select(patient);
    repo.fail = true;
    await vm.load();
    expect(vm.patients, isEmpty);
    expect(vm.owners, isEmpty);
    expect(vm.selected, isNull);
    expect(vm.events, isEmpty);
    vm.dispose();
  });
  test(
    'Respuesta tardía no repone datos tras cerrar pantalla; clínica ajena rechazada',
    () async {
      final repo = FakePatients()..pending = Completer<List<PatientEvent>>();
      final vm = PatientViewModel(repo, membership(ClinicRole.mvz));
      final task = vm.select(patient);
      vm.dispose();
      repo.pending!.complete([event(EventKind.weight)]);
      await task;
      expect(vm.events, isEmpty);
      expect(vm.selected, isNull);
      final other = PatientViewModel(
        FakePatients(),
        membership(ClinicRole.mvz),
      );
      await expectLater(
        other.select(
          const VetPatient(
            id: 'x',
            clinicId: 'other',
            name: 'X',
            species: 'X',
            breed: '',
            sex: 'sin especificar',
          ),
        ),
        throwsStateError,
      );
      other.dispose();
    },
  );
  testWidgets('Pantalla móvil de auxiliar oculta contactos y consentimientos', (
    tester,
  ) async {
    phone(tester);
    final repo = FakePatients()
      ..rows = [
        event(EventKind.weight, data: {'date': '2026-01-01', 'kg': '1.5'}),
        event(
          EventKind.allergy,
          data: {
            'date': '2026-01-01',
            'substance': 'Sustancia ficticia',
            'reaction': 'Reacción ficticia',
            'notes': '',
          },
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              PatientsScreen(
                repository: repo,
                member: membership(ClinicRole.auxiliar),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paciente ficticio'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tutor reservado'), findsNothing);
    expect(find.text('Agregar consentimiento'), findsNothing);
    // Brief alert and original chronological entry remain visible.
    expect(find.textContaining('Sustancia ficticia'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Dictado crea borrador revisable y no guarda sin revisar', (
    tester,
  ) async {
    final voice = FakeVoice();
    int writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EventForm(
          kind: EventKind.soap,
          patient: patient,
          voice: voice,
          save: (data, op) async {
            writes++;
            return null;
          },
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo de consulta'),
      'Consulta ficticia',
    );
    await tester.scrollUntilVisible(
      find.text('Dictar en español'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Dictar en español'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('S · Subjetivo'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'S · Subjetivo'))
          .controller!
          .text,
      'Texto ficticio dictado para revisión',
    );
    await tester.scrollUntilVisible(
      find.text('Detener dictado'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Detener dictado'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Guardar en el expediente'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Guardar en el expediente'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Revisa la nota antes de guardarla.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(voice.stopped, true);
  });
  testWidgets('Cambiar sesión cierra formularios con datos privados', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeAuth()..rows = [membership(ClinicRole.admin)];
    final auth = AuthViewModel(fake);
    await auth.start();
    final settings = SettingsRepository();
    final core = CoreViewModel(settings, await settings.load())
      ..navigate('Pacientes');
    await tester.pumpWidget(
      VetDosisApp(
        model: core,
        auth: auth,
        requireAuth: true,
        patients: FakePatients(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo paciente'));
    await tester.pumpAndSettle();
    expect(find.byType(PatientForm), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Crear paciente'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Crear paciente'), findsOneWidget);
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(PatientForm), findsNothing);
    expect(find.text('Crear paciente'), findsNothing);
    expect(find.text('Nombre del paciente'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    core.dispose();
    await fake.controller.close();
  });
  testWidgets(
    'Cambiar el consentimiento invalida aceptación y firma anteriores',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EventForm(
            kind: EventKind.consent,
            patient: patient,
            voice: FakeVoice(),
            save: (data, operationId) async => null,
          ),
        ),
      );
      final bodyScroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('El tutor leyó y acepta el texto indicado.'),
        300,
        scrollable: bodyScroll,
      );
      await tester.tap(find.text('El tutor leyó y acepta el texto indicado.'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
      await tester.scrollUntilVisible(
        find.byType(SignaturePad),
        200,
        scrollable: bodyScroll,
      );
      final canvas = find
          .descendant(
            of: find.byType(SignaturePad),
            matching: find.byType(GestureDetector),
          )
          .first;
      await tester.ensureVisible(canvas);
      final gesture = await tester.startGesture(tester.getCenter(canvas));
      await gesture.moveBy(const Offset(40, 20));
      await gesture.moveBy(const Offset(20, -10));
      await gesture.up();
      await tester.pumpAndSettle();
      final drawing = find.descendant(
        of: find.byType(SignaturePad),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is SignaturePainter,
        ),
      );
      expect(
        (tester.widget<CustomPaint>(drawing).painter as SignaturePainter)
            .points,
        isNotEmpty,
      );
      await tester.scrollUntilVisible(
        find.text('Texto del consentimiento aprobado por la clínica'),
        -300,
        scrollable: bodyScroll,
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Texto del consentimiento aprobado por la clínica',
        ),
        'Texto ficticio modificado',
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('El tutor leyó y acepta el texto indicado.'),
        300,
        scrollable: bodyScroll,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tester.scrollUntilVisible(
        find.byType(SignaturePad),
        200,
        scrollable: bodyScroll,
      );
      expect(
        (tester.widget<CustomPaint>(drawing).painter as SignaturePainter)
            .points,
        isEmpty,
      );
    },
  );
}
