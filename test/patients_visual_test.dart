import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/home_pilot.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patient_catalog.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patients_screen.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patient_form.dart';
import 'patients_test.dart' show FakePatients, membership, event;

const demoDog = VetPatient(
  id: 'dog',
  clinicId: 'a',
  name: 'Lúna DEMO',
  species: 'Canino',
  breed: 'Mestizo',
  sex: 'hembra',
);
const demoCat = VetPatient(
  id: 'cat',
  clinicId: 'a',
  name: 'Michi DEMO',
  species: 'Felino',
  breed: '',
  sex: 'macho',
);

class CatalogPatients extends FakePatients {
  final roster = <VetPatient>[demoDog, demoCat];
  bool failWrite = false;
  final attempts = <String>[];
  Map<String, dynamic>? savedOwner;
  @override
  Future<List<VetPatient>> patients(String clinicId) async {
    if (this.fail) throw StateError('unavailable');
    return roster;
  }

  @override
  Future<String> createPatient(
    String clinicId,
    Map<String, dynamic> p,
    Map<String, dynamic>? o,
    String op,
  ) async {
    attempts.add(op);
    if (failWrite) {
      failWrite = false;
      throw StateError('unavailable');
    }
    savedOwner = o;
    roster.add(
      VetPatient(
        id: 'new',
        clinicId: clinicId,
        name: p['name'] as String,
        species: p['species'] as String,
        breed: '',
        sex: 'sin especificar',
      ),
    );
    writes++;
    return 'new';
  }
}

Future<void> host(
  WidgetTester tester,
  CatalogPatients repo, {
  ClinicRole role = ClinicRole.admin,
  Brightness brightness = Brightness.light,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: homePilotTheme(ThemeData(brightness: brightness)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PatientsScreen(repository: repo, member: membership(role)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Search ignores accents and combines with actual species filters',
    (tester) async {
      final repo = CatalogPatients();
      await host(tester, repo);
      await tester.enterText(find.byType(TextField), 'luna');
      await tester.pump();
      expect(find.text('Lúna DEMO'), findsOneWidget);
      expect(find.text('Michi DEMO'), findsNothing);
      await tester.tap(find.text('Felino'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No hay pacientes que coincidan'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Limpiar búsqueda y filtros'));
      await tester.tap(find.text('Limpiar búsqueda y filtros'));
      await tester.pumpAndSettle();
      expect(find.text('Lúna DEMO'), findsOneWidget);
      expect(find.text('Michi DEMO'), findsOneWidget);
      expect(
        find.text('2 coincidencias de 2 pacientes cargados'),
        findsOneWidget,
      );
      expect(repo.writes, 0);
    },
  );
  testWidgets(
    'Create retains fields after failure and retries the same operation',
    (tester) async {
      final repo = CatalogPatients()..failWrite = true;
      await host(tester, repo);
      await tester.tap(find.text('Nuevo paciente'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(PatientForm))).colorScheme.primary,
        homePilotTheme(ThemeData()).colorScheme.primary,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del paciente'),
        'Nuevo DEMO',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Especie'),
        'Canino',
      );
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>).at(1),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar tutor nuevo').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del tutor'),
        'Tutor DEMO',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Teléfono internacional (opcional, ej. +52…)',
        ),
        '+520000000000',
      );
      await tester.scrollUntilVisible(
        find.text('Crear paciente'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Crear paciente'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudo guardar.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Nombre del paciente'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Nombre del paciente'),
            )
            .controller!
            .text,
        'Nuevo DEMO',
      );
      await tester.scrollUntilVisible(
        find.text('Crear paciente'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Crear paciente'));
      await tester.pumpAndSettle();
      expect(find.byType(PatientForm), findsNothing);
      expect(find.text('Nuevo DEMO'), findsOneWidget);
      expect(repo.attempts.length, 2);
      expect(repo.attempts.toSet().length, 1);
      expect(repo.writes, 1);
      expect(repo.savedOwner?['phone'], '+520000000000');
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('Record protects contacts and fits large text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CatalogPatients()
        ..rows = [
          event(
            EventKind.allergy,
            data: {
              'date': '2026-10-18',
              'substance': 'Alergia DEMO',
              'reaction': 'Reacción DEMO',
              'notes': '',
            },
          ),
        ];
      await host(
        tester,
        repo,
        role: ClinicRole.auxiliar,
        brightness: brightness,
        scale: 2,
      );
      await tester.ensureVisible(find.text('Lúna DEMO'));
      await tester.tap(find.text('Lúna DEMO'));
      await tester.pumpAndSettle();
      expect(find.byType(PatientIdentity), findsOneWidget);
      // Brief alert and original chronological entry remain visible.
      expect(find.textContaining('Alergia DEMO'), findsNWidgets(2));
      expect(find.textContaining('Tutor reservado'), findsNothing);
      expect(find.text('Nuevo paciente'), findsNothing);
      expect(repo.ownerReads, 0);
      expect(repo.eventReads, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('New patient form fits 320px and text at 200 percent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await host(tester, CatalogPatients(), scale: 2);
    await tester.ensureVisible(find.text('Nuevo paciente'));
    await tester.tap(find.text('Nuevo paciente'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Crear paciente'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
