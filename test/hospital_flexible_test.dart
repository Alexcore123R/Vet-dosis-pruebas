import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_forms.dart';
import 'patients_test.dart' show patient;
import 'hospital_test.dart' show stay;

void main() {
  test('Missing cage is explicit and other required text stays required', () {
    final s = HospitalStay.read({
      'id': 's',
      'clinic_id': 'c',
      'patient_id': 'p',
      'cage': null,
      'vet_patients': {'name': 'Synthetic', 'species': 'synthetic'},
      'admitted_at': '2026-10-16T00:00:00Z',
      'version': 1,
    });
    expect(s.cage, '');
    expect(s.cageLabel, 'Sin asignar');
    expect(hospitalText(' ', allowEmpty: true), '');
    expect(() => hospitalText(' '), throwsFormatException);
  });
  testWidgets(
    'Admission can save with just patient when optional cage is supported',
    (tester) async {
      String? cage;
      await tester.pumpWidget(
        MaterialApp(
          home: HospitalAdmitForm(
            patients: const [patient],
            optionalCage: true,
            save: (p, c, operation) async {
              cage = c;
              return false;
            },
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Paciente ficticio').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(cage, '');
      expect(find.textContaining('temperatura'), findsNothing);
      expect(find.textContaining('peso'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Legacy admission keeps cage validation until server migration', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HospitalAdmitForm(
          patients: const [patient],
          save: (_, c, operation) async {
            saves++;
            return false;
          },
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Paciente ficticio').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(saves, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Moving can clear cage without a mandatory reason', (
    tester,
  ) async {
    String? cage, reason;
    await tester.pumpWidget(
      MaterialApp(
        home: HospitalCageForm(
          stay: stay(),
          save: (c, r, op) async {
            cage = c;
            reason = r;
            return false;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('Guardar ubicación'));
    await tester.pumpAndSettle();
    expect(cage, '');
    expect(reason, '');
    await tester.pumpWidget(const SizedBox());
  });
}
