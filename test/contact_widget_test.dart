import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/patients/presentation/contact_actions.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patient_contact_panel.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_contacts.dart';
import 'package:vetdosis_pro/modules/operations/presentation/appointment_links_panel.dart';

class Contacts implements PatientContactRepository {
  bool fail = false;
  @override
  Future<Map<String, dynamic>> contact(String clinic, String patient) async {
    if (fail) throw StateError('revoked');
    return {
      'schema_version': 1,
      'clinic_id': clinic,
      'patient_id': patient,
      'owner': {
        'id': 'o',
        'name': 'Tutor sintético',
        'phone': '+520000000001',
        'address': 'Dirección sintética',
        'phone_alt': '',
        'email': '',
        'contact_name': '',
        'contact_phone': '',
        'contact_relationship': '',
        'contact_authorized': false,
        'contact_version': 1,
      },
      'can_write': true,
      'attempts': [],
    };
  }

  @override
  Future<void> saveContact(
    String c,
    String p,
    String o,
    int v,
    Map<String, dynamic> d,
    String op,
  ) async {}
  @override
  Future<void> logContact(
    String c,
    String p,
    String o,
    Map<String, dynamic> d,
    String op,
  ) async {}
}

void main() {
  testWidgets(
    'Contacts are removed after background and failed permission recheck',
    (tester) async {
      final repo = Contacts();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PatientContactPanel(
                repository: repo,
                clinic: 'c',
                patient: 'p',
                patientName: 'Paciente sintético',
                onSaved: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('+520000000001'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.textContaining('+520000000001'), findsNothing);
      repo.fail = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('+520000000001'), findsNothing);
      expect(find.textContaining('No se pudieron comprobar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Phone contact insertion opens only after explicit confirmation',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        patientContactChannel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          patientContactChannel,
          null,
        ),
      );
      final actions = ContactActions(
        owner: const {'name': 'Tutor sintético', 'phone': '+520000000001'},
        patientName: 'Paciente',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => actions.phoneAgenda(context, insert: true),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'insertContact');
      expect((calls.single.arguments as Map).keys.toSet(), {'name', 'phone'});
    },
  );
  testWidgets('A billing query failure does not imply unpaid', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppointmentLinksPanel(data: null, patientName: 'Paciente'),
        ),
      ),
    );
    expect(find.textContaining('Estado de pago no disponible'), findsOneWidget);
    expect(find.textContaining('Pendiente de pago'), findsNothing);
  });
  testWidgets(
    'Contact and payment cards fit 320px and 200 percent text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ContactActions(
                      owner: {
                        'name': 'Tutor sintético',
                        'phone': '+520000000001',
                        'phone_alt': '+520000000002',
                        'address': 'Dirección sintética de prueba',
                      },
                      patientName: 'Paciente sintético',
                    ),
                    AppointmentLinksPanel(
                      data: {
                        'billing': {
                          'state': 'partial',
                          'total': '150',
                          'paid': '100',
                          'charge_count': 2,
                        },
                      },
                      patientName: 'Paciente sintético',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
