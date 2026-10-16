import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_models.dart';
import 'package:vetdosis_pro/modules/prescribing/domain/prescribing_repository.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_view_model.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'prescribing_test.dart' show RxFake, RxClinicalFake, auxiliary;

class OperationalFake extends RxFake implements MedicationPermissionRepository {
  Map<String, dynamic>? permissions = {'schema_version': 1, 'scopes': []};
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>?> medicationPermissions(
    String c,
    String? caseId,
  ) async => permissions;
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    calls.add(command);
    if (this.fail) {
      throw StateError('synthetic outage');
    }
    if (command == 'rx_profiles') {
      return [
        {'user_id': auxiliary.userId, 'authorized': true},
      ];
    }
    if (command == 'rx_medications') {
      return [
        {'id': 'record', 'can_correct': true},
      ];
    }
    return [];
  }
}

class CaseFake extends RxClinicalFake {
  @override
  Future<List<ClinicalCase>> cases(String clinic, String? patient) async => [
    ClinicalCase({'id': 'case', 'responsible_id': auxiliary.userId}),
  ];
}

void main() {
  test(
    'Legacy professional label cannot grant new operational permissions',
    () async {
      final repo = OperationalFake();
      final vm = PrescribingViewModel(repo, CaseFake(), auxiliary, null);
      await vm.load(selectedCase: 'case');
      expect(vm.professional, true);
      expect(vm.responsible, true);
      expect(vm.canManageVials, false);
      expect(vm.canValidateMedication, false);
      expect(vm.canReportMedication, false);
      expect(vm.canScheduleMedication, false);
      expect(repo.calls, isNot(contains('rx_vials')));
      expect(vm.canCorrectMedication(vm.medications.single), false);
      vm.dispose();
    },
  );
  test('Administer, draw, validate and manage are independent', () async {
    final repo = OperationalFake()
      ..permissions = {
        'schema_version': 1,
        'vial.read': true,
        'vial.manage': false,
        'medication.validate': false,
        'hospital.schedule': true,
        'hospital.read': false,
        'scopes': [
          {'scope': 'cuidados', 'administer': true, 'draw': false},
          {'scope': 'cirugia', 'administer': false, 'draw': true},
        ],
      };
    final vm = PrescribingViewModel(repo, CaseFake(), auxiliary, null);
    await vm.load(selectedCase: 'case');
    expect(vm.canReportMedication, true);
    expect(vm.medicationScopes, {'cuidados': 'Cuidados'});
    expect(vm.canDraw('cuidados'), false);
    expect(vm.canDraw('cirugia'), false);
    expect(vm.canValidateMedication, false);
    expect(vm.canManageVials, false);
    expect(vm.canScheduleMedication, false);
    expect(repo.calls, contains('rx_vials'));
    repo.permissions = {...repo.permissions!, 'medication.validate': true};
    await vm.load();
    final record = vm.medications.single;
    expect(vm.canCorrectMedication(record), true);
    repo.fail = true;
    await vm.load();
    expect(vm.canCorrectMedication(record), false);
    expect(vm.canReportMedication, false);
    expect(vm.canManageVials, false);
    vm.dispose();
  });
  test('Missing or unknown established contract fails closed', () async {
    final repo = OperationalFake()
      ..permissions = {'schema_version': 1, 'vial.manage': true, 'scopes': []};
    final vm = PrescribingViewModel(repo, CaseFake(), auxiliary, null);
    await vm.load(selectedCase: 'case');
    expect(vm.canManageVials, true);
    repo.permissions = null;
    await vm.load();
    expect(vm.error, isNotNull);
    expect(vm.operationalKnown, true);
    expect(vm.canManageVials, false);
    repo.permissions = {'schema_version': 2};
    await vm.load();
    expect(vm.error, isNotNull);
    expect(vm.canReportMedication, false);
    vm.dispose();
  });
  test('Duplicate confirmation explains that no second draw was saved', () {
    expect(
      rxError(StateError('task_already_confirmed')),
      contains('no se registró otra toma'),
    );
  });
}
