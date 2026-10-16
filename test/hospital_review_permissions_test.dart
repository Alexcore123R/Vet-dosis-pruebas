import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_view_model.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_forms.dart';
import 'hospital_test.dart'
    show FakeAlarms, FakeHospital, alerts, member, stay, noon;

HospitalTask review({Map<String, dynamic>? actions}) => HospitalTask(
  id: 'review',
  stayId: 'stay-a',
  kind: 'revision',
  label: 'Synthetic review',
  instructions: 'Synthetic',
  dueAt: noon,
  escalationMinutes: 15,
  state: HospitalTaskState.pending,
  version: 1,
  actions: actions,
);

void main() {
  test(
    'Explicit snapshot never promotes an admin or restores legacy authority',
    () async {
      final a = await alerts(FakeAlarms(supported: false));
      final t = review();
      final repo = FakeHospital()
        ..snapshot = HospitalSnapshot(
          [stay()],
          [t],
          typedReviews: true,
          permissions: const {},
        );
      final vm = HospitalViewModel(repo, member(ClinicRole.admin), a);
      await vm.refresh();
      expect(vm.canSchedule, false);
      expect(vm.canDischarge, false);
      expect(vm.canTask(t, 'perform'), false);
      expect(await vm.perform(t), false);
      expect(await vm.cancel(t, 'Synthetic'), false);
      expect(await vm.discharge(stay(), 'Synthetic'), false);
      expect(repo.writes, 0);
      vm.dispose();
      a.dispose();
    },
  );
  test(
    'Per-task rights are separate and stale rights cannot survive load failure',
    () async {
      final a = await alerts(FakeAlarms(supported: false));
      final t = review(
        actions: const {'perform': true, 'snooze': false, 'cancel': false},
      );
      final repo = FakeHospital()
        ..snapshot = HospitalSnapshot(
          [stay()],
          [t],
          typedReviews: true,
          permissions: const {'hospital.schedule': false},
        );
      final vm = HospitalViewModel(repo, member(ClinicRole.auxiliar), a);
      await vm.refresh();
      expect(vm.canTask(t, 'perform'), true);
      expect(vm.canTask(t, 'snooze'), false);
      expect(vm.canTask(t, 'cancel'), false);
      expect(await vm.snooze(t, 10, 'Synthetic'), false);
      expect(repo.writes, 0);
      repo.fail = true;
      await vm.refresh();
      expect(vm.canTask(t, 'perform'), false);
      expect(await vm.perform(t), false);
      expect(repo.writes, 0);
      vm.dispose();
      a.dispose();
    },
  );
  testWidgets(
    'Typed review form has no default procedure or medication choice',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HospitalOrderForm(
            stay: stay(),
            reviewTypes: const [
              HospitalReviewType('type-a', 'Synthetic selected procedure'),
            ],
            save: (_, a, b, c, d, e) async => false,
          ),
        ),
      );
      final finder = find.byType(DropdownButtonFormField<String>);
      expect(
        tester.widget<DropdownButtonFormField<String>>(finder).initialValue,
        isNull,
      );
      expect(find.text('Programar revisión'), findsOneWidget);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(find.text('Medicación'), findsNothing);
      await tester.tap(find.text('Synthetic selected procedure').last);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic selected procedure'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('No configured procedures does not manufacture a generic type', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HospitalOrderForm(
          stay: stay(),
          reviewTypes: const [],
          save: (_, a, b, c, d, e) async => false,
        ),
      ),
    );
    expect(find.textContaining('No hay tipos activos.'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
