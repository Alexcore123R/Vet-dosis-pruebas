import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_activity.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patient_catalog.dart';
import 'package:vetdosis_pro/modules/patients/presentation/patients_screen.dart';
import 'patients_visual_test.dart' show CatalogPatients;
import 'patients_test.dart' show membership;
import 'patient_activity_test.dart' show data, row;

class ActivePatients extends CatalogPatients
    implements PatientActivityRepository {
  bool unavailable = false;
  @override
  Future<PatientActivitySnapshot> activity(String clinic) async {
    if (unavailable) throw StateError('revoked');
    return PatientActivitySnapshot.read(
      data(
        clinic: clinic,
        rows: [
          row('dog', 'hospitalized', 's1'),
          row('dog', 'consultation', 'a1'),
        ],
      ),
      clinic,
    );
  }
}

void main() {
  testWidgets(
    'Activity combines with species/search without duplicating patients',
    (tester) async {
      final repo = ActivePatients();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PatientsScreen(
                repository: repo,
                member: membership(ClinicRole.admin),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PatientCatalogTile), findsNWidgets(2));
      await tester.tap(find.text('Hospitalizados (1)'));
      await tester.pumpAndSettle();
      expect(find.byType(PatientCatalogTile), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'michi');
      await tester.pumpAndSettle();
      expect(find.byType(PatientCatalogTile), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Backgrounding clears activity and failure after resume does not restore it',
    (tester) async {
      final repo = ActivePatients();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PatientsScreen(
                repository: repo,
                member: membership(ClinicRole.admin),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hospitalizados (1)'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Hospitalizados (1)'), findsNothing);
      repo.unavailable = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Hospitalizados (1)'), findsNothing);
      expect(
        find.textContaining('No se pudo comprobar la actividad'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Activity cards fit narrow screens and enlarged text in both themes',
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
            home: Scaffold(
              body: SingleChildScrollView(
                child: PatientsScreen(
                  key: ValueKey(brightness),
                  repository: ActivePatients(),
                  member: membership(ClinicRole.admin),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
