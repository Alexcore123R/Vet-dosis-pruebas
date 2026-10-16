import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/inventory/domain/inventory_repository.dart';
import 'package:vetdosis_pro/modules/inventory/presentation/inventory_view_model.dart';
import 'package:vetdosis_pro/modules/inventory/presentation/workflow_screen.dart';
import 'inventory_test.dart' show Repo, member, data;

class DispensingRepo extends Repo implements DispensingPermissionRepository {
  Map<String, dynamic>? contract = {
    'schema_version': 1,
    'mode': 'verified_dispensing',
    'can_dispense': false,
    'can_authorize': false,
  };
  @override
  Future<Map<String, dynamic>?> dispensingPermissions(String clinic) async =>
      contract;
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    if (command == 'inv_workflow_dashboard') {
      return {
        'charges': [],
        'deliveries': [],
        'applications': [],
        'grants': [],
      };
    }
    if (command == 'inv_dashboard') return {...data(), 'professional': true};
    return super.read(command, args);
  }
}

void main() {
  test(
    'server permission overrides the legacy professional flag; contract loss fails closed',
    () async {
      final repo = DispensingRepo();
      final model = InventoryViewModel(repo, member);
      addTearDown(model.dispose);
      await model.load();
      expect(model.dashboard!['professional'], isTrue);
      expect(model.canDispense, isFalse);
      expect(model.canAuthorizeDispensing, isFalse);
      repo.contract!['can_dispense'] = true;
      repo.contract!['can_authorize'] = true;
      await model.load();
      expect(model.canDispense, isTrue);
      expect(model.canAuthorizeDispensing, isTrue);
      repo.contract = null;
      await model.load();
      expect(model.dashboard, isNull);
      expect(model.canDispense, isFalse);
    },
  );
  test(
    'unknown contract version cannot expose previous inventory data',
    () async {
      final repo = DispensingRepo();
      final model = InventoryViewModel(repo, member);
      addTearDown(model.dispose);
      await model.load();
      repo.contract!['schema_version'] = 2;
      await model.load();
      expect(model.error, isNotNull);
      expect(model.products, isEmpty);
      expect(model.canDispense, isFalse);
    },
  );
  testWidgets(
    'new dispensing contract removes ordinary delegation and physical delivery for non-MVZ',
    (tester) async {
      final repo = DispensingRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryWorkflowScreen(
            repository: repo,
            member: member,
            dashboard: {...data(), 'professional': true},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delegar entrega ordinaria'), findsNothing);
      expect(find.text('Registrar entrega física'), findsNothing);
      expect(find.textContaining('Las delegaciones antiguas'), findsOneWidget);
    },
  );
  testWidgets(
    'explicit dispensing capability exposes delivery without re-enabling legacy delegation',
    (tester) async {
      final repo = DispensingRepo();
      repo.contract!['can_dispense'] = true;
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryWorkflowScreen(
            repository: repo,
            member: member,
            dashboard: data(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registrar entrega física'), findsOneWidget);
      expect(find.text('Delegar entrega ordinaria'), findsNothing);
      expect(repo.writes, isEmpty);
    },
  );
}
