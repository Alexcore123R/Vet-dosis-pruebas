import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/prescribing/domain/prescribing_repository.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/prescribing_view_model.dart';
import 'prescribing_test.dart' show RxFake, RxClinicalFake, auxiliary;

class ReportRepo extends RxFake implements ReportPermissionRepository {
  Map<String, dynamic>? contract = {
    'schema_version': 1,
    'mode': 'controlled_reference',
    'can_prepare': false,
    'can_issue': false,
  };
  bool denyExport = false;
  int exports = 0;
  @override
  Future<Map<String, dynamic>?> reportPermissions(String clinic) async =>
      contract;
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    if (command == 'rx_reports') {
      return [
        {'id': 'report', 'state': 'issued'},
      ];
    }
    if (command == 'rx_report_export') {
      exports++;
      if (denyExport) throw StateError('revoked');
      return {
        'id': args['p_id'],
        'state': 'issued',
        'snapshot': {'entries': []},
      };
    }
    return super.read(command, args);
  }
}

void main() {
  test(
    'report authority follows explicit contract, independent of job or legacy profile',
    () async {
      final repo = ReportRepo();
      final model = PrescribingViewModel(
        repo,
        RxClinicalFake(),
        auxiliary,
        null,
      );
      addTearDown(model.dispose);
      await model.load();
      expect(model.error, isNull);
      expect(model.canPrepareReport, isFalse);
      repo.contract!['can_prepare'] = true;
      await model.load();
      expect(model.canPrepareReport, isTrue);
      expect(model.canIssueReport, isFalse);
      repo.contract!['can_issue'] = true;
      await model.load();
      expect(model.canIssueReport, isTrue);
      repo.contract = null;
      await model.load();
      expect(model.error, isNotNull);
      expect(model.reports, isEmpty);
      expect(model.canPrepareReport, isFalse);
    },
  );
  test(
    'unknown or malformed report contract clears previous content',
    () async {
      for (final bad in [
        {
          'schema_version': 2,
          'mode': 'controlled_reference',
          'can_prepare': true,
          'can_issue': true,
        },
        {
          'schema_version': 1,
          'mode': 'unknown',
          'can_prepare': true,
          'can_issue': true,
        },
        {
          'schema_version': 1,
          'mode': 'controlled_reference',
          'can_prepare': 'true',
          'can_issue': true,
        },
      ]) {
        final repo = ReportRepo();
        final model = PrescribingViewModel(
          repo,
          RxClinicalFake(),
          auxiliary,
          null,
        );
        await model.load();
        repo.contract = bad;
        await model.load();
        expect(model.reports, isEmpty);
        expect(model.canIssueReport, isFalse);
        model.dispose();
      }
    },
  );
  test(
    'every export rechecks server; revocation removes cached report and capabilities',
    () async {
      final repo = ReportRepo();
      final model = PrescribingViewModel(
        repo,
        RxClinicalFake(),
        auxiliary,
        null,
      );
      addTearDown(model.dispose);
      await model.load();
      expect((await model.reportExport('report'))['state'], 'issued');
      repo.denyExport = true;
      await expectLater(model.reportExport('report'), throwsStateError);
      expect(repo.exports, 2);
      expect(model.reports, isEmpty);
      expect(model.canIssueReport, isFalse);
    },
  );
}
