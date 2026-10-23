import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/core/domain/navigation_access.dart';
import 'package:vetdosis_pro/modules/inventory/domain/inventory_repository.dart';
import 'package:vetdosis_pro/modules/inventory/presentation/inventory_screen.dart';
import 'package:vetdosis_pro/modules/inventory/presentation/inventory_view_model.dart';
import 'dispensing_permissions_test.dart' show DispensingRepo;
import 'package:vetdosis_pro/modules/inventory/presentation/payments_view_model.dart';
import 'inventory_test.dart' show data, member;

class ManagementRepo extends DispensingRepo
    implements InventoryManagementRepository {
  Map<String, dynamic>? management = {
    'schema_version': 1,
    'mode': 'explicit_inventory',
    'actions': <String, bool>{},
    'can_link_vial': false,
    'can_prepare_charge': false,
  };
  final reads = <String>[];
  bool activeShift = false;
  @override
  Future<Map<String, dynamic>?> managementPermissions(String clinic) async =>
      management;
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    reads.add(command);
    if (command == 'inv_dashboard') {
      return {
        ...data(),
        'professional': true,
        'shifts': activeShift
            ? [
                {
                  'id': 'shift',
                  'cashier_id': 'aux',
                  'closed_at': null,
                  'opened_at': 'Synthetic date',
                },
              ]
            : [],
      };
    }
    if (command == 'inv_billable_services') return [];
    return super.read(command, args);
  }
}

class SupplierRepo extends ManagementRepo {
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    final result = await super.read(command, args);
    if (command == 'inv_dashboard') {
      final product = Map<String, dynamic>.from(
        (result['products'] as List).first as Map,
      );
      result['products'] = [
        {...product, 'proveedor': 'Proveedor de prueba'},
        {...product, 'id': 'second', 'proveedor': 'Proveedor de prueba'},
      ];
    }
    return result;
  }
}

Future<void> openInventory(
  WidgetTester tester,
  ManagementRepo repo, {
  ClinicMembership selected = member,
  String section = 'stock',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InventoryScreen(
            repository: repo,
            member: selected,
            initialSection: section,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Supplier list groups the existing inventory records on mobile', (
    tester,
  ) async {
    await openInventory(tester, SupplierRepo(), section: 'suppliers');
    expect(find.text('Proveedor de prueba'), findsOneWidget);
    expect(find.text('2 productos vinculados'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'read-only administrator has no operational grants, explicit receiver can only receive',
    () async {
      final repo = ManagementRepo();
      const admin = ClinicMembership(
        clinicId: 'clinic',
        clinicName: 'Synthetic',
        userId: 'aux',
        role: ClinicRole.admin,
      );
      final model = InventoryViewModel(repo, admin);
      addTearDown(model.dispose);
      await model.load();
      expect(model.canManage, isFalse);
      expect(model.canCollect, isFalse);
      expect(model.canAdjust, isFalse);
      expect(model.canReadFinance, isFalse);
      repo.management!['actions'] = {'inventory.receive': true};
      await model.load();
      expect(model.canReceive, isTrue);
      expect(model.canManage, isFalse);
      expect(model.canCollect, isFalse);
      repo.management!['actions'] = {'sales.collect': true};
      await model.load();
      expect(model.canCollect, isTrue);
      expect(model.canMoveCash, isFalse);
      expect(model.canReverse, isFalse);
      expect(model.canManual, isFalse);
    },
  );
  test(
    'known management contract cannot disappear or downgrade to role-based access',
    () async {
      final repo = ManagementRepo();
      repo.management!['actions'] = {'inventory.manage': true};
      final model = InventoryViewModel(repo, member);
      addTearDown(model.dispose);
      await model.load();
      expect(model.canManage, isTrue);
      repo.management = null;
      await model.load();
      expect(model.dashboard, isNull);
      expect(model.canManage, isFalse);
      expect(model.canCollect, isFalse);
    },
  );
  test(
    'unknown management version clears previous data and capabilities',
    () async {
      final repo = ManagementRepo();
      final model = InventoryViewModel(repo, member);
      addTearDown(model.dispose);
      await model.load();
      repo.management!['schema_version'] = 2;
      await model.load();
      expect(model.error, isNotNull);
      expect(model.products, isEmpty);
      expect(model.canCollect, isFalse);
    },
  );
  testWidgets(
    'read-only administrator sees no catalog writes or unmigrated payment route',
    (tester) async {
      final repo = ManagementRepo();
      const admin = ClinicMembership(
        clinicId: 'clinic',
        clinicName: 'Synthetic',
        userId: 'aux',
        role: ClinicRole.admin,
      );
      await openInventory(tester, repo, selected: admin);
      expect(find.text('Nuevo producto'), findsNothing);
      expect(find.text('Editar datos/precios'), findsNothing);
      expect(find.text('Entrada de lote'), findsNothing);
      expect(find.text('Cobros, pagos y referencias externas'), findsNothing);
      expect(find.text('Vincular frasco abierto'), findsNothing);
    },
  );
  testWidgets(
    'receiving capability is separate from catalog, prices and photo writes',
    (tester) async {
      final repo = ManagementRepo();
      repo.management!['actions'] = {'inventory.receive': true};
      await openInventory(tester, repo);
      expect(find.text('Entrada de lote'), findsOneWidget);
      expect(find.text('Editar datos/precios'), findsNothing);
      expect(find.text('Foto con cámara'), findsNothing);
    },
  );
  testWidgets(
    'cashier opens billable services through the new safe RPC, not ops aggregate',
    (tester) async {
      final repo = ManagementRepo();
      repo.activeShift = true;
      repo.management!['actions'] = {'sales.collect': true};
      await openInventory(tester, repo, section: 'cash');
      final sale = find.text('Nueva venta');
      await tester.ensureVisible(sale);
      await tester.tap(sale);
      await tester.pumpAndSettle();
      expect(repo.reads, contains('inv_billable_services'));
      expect(repo.reads, isNot(contains('ops_dashboard')));
      expect(find.text('Servicio manual'), findsNothing);
    },
  );
  test(
    'visual job does not hide inventory entry; the server decides access',
    () {
      const stylist = ClinicMembership(
        clinicId: 'clinic',
        clinicName: 'Synthetic',
        userId: 'aux',
        role: ClinicRole.estilista,
      );
      expect(navigationAllowed('Inventario', stylist), isTrue);
      expect(navigationAllowed('Caja', stylist), isTrue);
    },
  );
  test('failed fresh cut read clears the cached financial export', () async {
    final repo = ManagementRepo();
    final model = InventoryViewModel(repo, member);
    addTearDown(model.dispose);
    await model.load();
    await model.readCut('test');
    expect(model.cut, isNotNull);
    repo.fail = true;
    await expectLater(model.readCut('test'), throwsStateError);
    expect(model.cut, isNull);
    expect(model.error, isNotNull);
    expect(model.canCollect, isFalse);
  });
  test(
    'reference reporting, finance reading and reconciliation are separate',
    () async {
      final repo = ManagementRepo();
      final model = PaymentsViewModel(repo, 'clinic');
      addTearDown(model.dispose);
      await model.load();
      expect(model.canReport, isFalse);
      expect(model.canReconcile(true), isFalse);
      repo.management!['actions'] = {'sales.collect': true};
      await model.load();
      expect(model.canReport, isTrue);
      expect(model.canReconcile(true), isFalse);
      repo.management!['actions'] = {
        'sales.read': true,
        'sales.reconcile': true,
      };
      await model.load();
      expect(model.canReport, isFalse);
      expect(model.canReconcile(false), isTrue);
      repo.management = null;
      await model.load();
      expect(model.data, isEmpty);
      expect(model.canReconcile(true), isFalse);
    },
  );
  test(
    'malformed capability map is rejected instead of using a job label',
    () async {
      final repo = ManagementRepo();
      repo.management!['actions'] = 'invalid';
      final model = InventoryViewModel(repo, member);
      addTearDown(model.dispose);
      await model.load();
      expect(model.dashboard, isNull);
      expect(model.canManage, isFalse);
      expect(model.error, isNotNull);
    },
  );
}
