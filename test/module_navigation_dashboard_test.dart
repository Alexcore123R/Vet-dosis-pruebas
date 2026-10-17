import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/core/domain/module_access.dart';
import 'package:vetdosis_pro/modules/core/domain/navigation_access.dart';
import 'package:vetdosis_pro/modules/core/presentation/module_access_boundary.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/dashboard_view_model.dart';
import 'package:vetdosis_pro/modules/inventory/domain/inventory_repository.dart';

const member = ClinicMembership(
  clinicId: 'clinic',
  clinicName: 'Synthetic clinic',
  userId: 'person',
  role: ClinicRole.admin,
);

Map<String, dynamic> contract({String enabled = ''}) => {
  'schema_version': 1,
  'mode': 'explicit_modules',
  'modules': {
    for (final name in const [
      'patients',
      'agenda',
      'hospital',
      'inventory',
      'sales',
      'prescriptions',
      'forms',
      'clinical',
      'statistics',
      'backup',
    ])
      name: name == enabled,
  },
  'summaries': {
    for (final name in const [
      'patients',
      'agenda',
      'hospital',
      'inventory',
      'sales',
    ])
      name: name == enabled,
  },
};

class AccessRepo implements ModuleAccessRepository {
  AccessRepo(this.response);
  final Future<Map<String, dynamic>> response;
  @override
  Future<Map<String, dynamic>> workspace(String clinicId) => response;
}

class SequenceAccessRepo implements ModuleAccessRepository {
  SequenceAccessRepo(this.responses);
  final List<Map<String, dynamic>> responses;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> workspace(String clinicId) async =>
      responses[calls++];
}

class InventoryProbe implements InventoryRepository {
  int reads = 0;
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    reads++;
    return {'products': [], 'shifts': []};
  }

  @override
  Future<void> photo(String a, String b, int c, Uint8List d, String e) async {}
  @override
  Future<String> photoUrl(String path) async => '';
  @override
  Future<dynamic> write(String command, Map<String, dynamic> args) async {}
}

void main() {
  test('explicit modules override visual administrator and remain narrow', () {
    final denied = ModuleAccess.read(contract());
    expect(navigationAllowed('Pacientes', member, denied), false);
    expect(navigationAllowed('Hospitalización', member, denied), false);
    expect(navigationAllowed('Respaldo', member, denied), false);
    expect(navigationAllowed('Estadísticas', member, denied), false);
    final inventory = ModuleAccess.read(contract(enabled: 'inventory'));
    expect(navigationAllowed('Inventario', member, inventory), true);
    expect(navigationAllowed('Caja', member, inventory), false);
    expect(navigationAllowed('Pacientes', member, inventory), false);
  });

  test('backup and statistics are independent server modules', () {
    final raw = contract();
    (raw['modules'] as Map)['backup'] = true;
    final backup = ModuleAccess.read(raw);
    expect(navigationAllowed('Respaldo', member, backup), true);
    expect(navigationAllowed('Estadísticas', member, backup), false);
  });

  test('unknown or incomplete module contracts fail closed', () {
    expect(
      () => ModuleAccess.read({...contract(), 'schema_version': 2}),
      throwsFormatException,
    );
    final incomplete = contract();
    (incomplete['modules'] as Map).remove('hospital');
    expect(() => ModuleAccess.read(incomplete), throwsFormatException);
    final incompleteSummary = contract();
    (incompleteSummary['summaries'] as Map).remove('sales');
    expect(() => ModuleAccess.read(incompleteSummary), throwsFormatException);
  });

  test('dashboard does not query a module omitted by the server', () async {
    final probe = InventoryProbe();
    final model = DashboardViewModel(
      member: member,
      inventory: probe,
      moduleAccess: ModuleAccess.read(contract()),
    );
    await model.load();
    expect(probe.reads, 0);
    expect(model.stock, isNull);
    model.dispose();
  });

  test('module management does not imply dashboard read access', () async {
    final raw = contract();
    (raw['modules'] as Map)['inventory'] = true;
    final access = ModuleAccess.read(raw);
    final probe = InventoryProbe();
    final model = DashboardViewModel(
      member: member,
      inventory: probe,
      moduleAccess: access,
    );
    expect(navigationAllowed('Inventario', member, access), true);
    await model.load();
    expect(probe.reads, 0);
    model.dispose();
  });

  testWidgets('failed permissions show retry without enabling modules', (
    tester,
  ) async {
    final repository = SequenceAccessRepo([{}, contract(enabled: 'inventory')]);
    await tester.pumpWidget(MaterialApp(
      home: ModuleAccessBoundary(
        member: member,
        repository: repository,
        revision: 0,
        builder: (access) => Scaffold(body: Text(
          navigationAllowed('Inventario', member, access)
              ? 'inventory-visible'
              : 'inventory-hidden',
        )),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('No se pudieron comprobar'), findsOneWidget);
    expect(find.text('inventory-hidden'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudieron comprobar'), findsNothing);
    expect(find.text('inventory-visible'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('identity change clears an earlier module contract', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    Widget app(ClinicMembership current, ModuleAccessRepository repository) =>
        MaterialApp(
          home: ModuleAccessBoundary(
            member: current,
            repository: repository,
            revision: 0,
            builder: (access) => Text(
              navigationAllowed('Inventario', current, access)
                  ? 'inventory-visible'
                  : 'inventory-hidden',
            ),
          ),
        );
    await tester.pumpWidget(app(member, AccessRepo(first.future)));
    expect(find.text('inventory-hidden'), findsOneWidget);
    first.complete(contract(enabled: 'inventory'));
    await tester.pump();
    expect(find.text('inventory-visible'), findsOneWidget);
    const next = ClinicMembership(
      clinicId: 'other-clinic',
      clinicName: 'Other',
      userId: 'other-person',
      role: ClinicRole.admin,
    );
    await tester.pumpWidget(app(next, AccessRepo(second.future)));
    expect(find.text('inventory-hidden'), findsOneWidget);
    second.complete(contract());
    await tester.pump();
  });

  testWidgets('session refresh replaces revoked module visibility', (
    tester,
  ) async {
    final repository = SequenceAccessRepo([
      contract(enabled: 'inventory'),
      contract(),
    ]);
    Widget app(int revision) => MaterialApp(
      home: ModuleAccessBoundary(
        member: member,
        repository: repository,
        revision: revision,
        builder: (access) => Text(
          navigationAllowed('Inventario', member, access)
              ? 'inventory-visible'
              : 'inventory-hidden',
        ),
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pump();
    expect(find.text('inventory-visible'), findsOneWidget);
    await tester.pumpWidget(app(1));
    expect(find.text('inventory-hidden'), findsOneWidget);
    await tester.pump();
    expect(find.text('inventory-hidden'), findsOneWidget);
    expect(repository.calls, 2);
  });
}
