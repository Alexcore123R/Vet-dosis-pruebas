import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/permissions/domain/permission_repository.dart';
import 'package:vetdosis_pro/modules/permissions/presentation/permission_screen.dart';
import 'support/fake_auth.dart';

const member = ClinicMembership(
  clinicId: 'a',
  clinicName: 'Clínica A',
  userId: 'user-a',
  role: ClinicRole.admin,
);

class PermissionFake extends FakeAuth implements PermissionRepository {
  bool manager = true, fail = false;
  List<Object?>? granted;
  @override
  Future<Map<String, dynamic>> permissions(String clinicId) async {
    if (fail) throw StateError('denied');
    return {
      'enforcement_enabled': false,
      'can_manage': manager,
      'can_review': false,
      'members': [
        {
          'user_id': 'user-a',
          'email': 'owner@example.test',
          'job_label': 'Recepción',
          'professional_current': false,
        },
      ],
      'catalog': [
        {
          'code': 'drug.administer',
          'label': 'Administrar medicamento',
          'procedure_scoped': true,
          'requires_professional': false,
        },
      ],
      'procedures': [
        {'id': 'procedure-a', 'name': 'Procedimiento A', 'active': true},
      ],
      'grants': [],
      'responsible': [],
    };
  }

  @override
  Future<Map<String, dynamic>> professionalEvidence(String clinicId) async => {
    'profiles': [],
    'verifications': [],
  };
  @override
  Future<void> grantPermission(
    String clinicId,
    String userId,
    String code,
    String? procedureId,
    DateTime until,
    String reason,
  ) async {
    granted = [clinicId, userId, code, procedureId, until, reason];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<AuthViewModel> mount(WidgetTester tester, PermissionFake repo) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  repo.rows = [member];
  final model = AuthViewModel(repo);
  await model.start();
  addTearDown(model.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: PermissionScreen(model: model, clinic: member),
    ),
  );
  await tester.pumpAndSettle();
  return model;
}

void main() {
  testWidgets('shows preparation separately from professional authority', (
    tester,
  ) async {
    await mount(tester, PermissionFake());
    expect(find.textContaining('La beta sigue en preparación'), findsOneWidget);
    expect(find.textContaining('el puesto no concede acceso'), findsOneWidget);
    expect(find.text('Sin habilitación vigente'), findsOneWidget);
    expect(find.text('Proponer responsable'), findsNothing);
    expect(find.text('Revisar evidencia'), findsNothing);
  });
  testWidgets('management fits a narrow phone without overflow', (
    tester,
  ) async {
    await mount(tester, PermissionFake());
    tester.view.physicalSize = const Size(360, 740);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Habilitación profesional'), 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('ordinary member cannot grant or edit jobs', (tester) async {
    await mount(tester, PermissionFake()..manager = false);
    expect(find.text('Conceder permiso'), findsNothing);
    expect(find.text('Editar puesto'), findsNothing);
    expect(find.text('Agregar tipo de procedimiento'), findsNothing);
  });
  testWidgets(
    'grant requires selected procedure, expiry, reason and confirmation',
    (tester) async {
      final repo = PermissionFake();
      await mount(tester, repo);
      await tester.tap(find.text('Conceder permiso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrar medicamento'));
      await tester.pumpAndSettle();
      expect(find.text('Tipo de procedimiento obligatorio'), findsOneWidget);
      expect(repo.granted, isNull);
      await tester.tap(find.text('Procedimiento A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar cambio'));
      await tester.pumpAndSettle();
      expect(find.text('Campo obligatorio'), findsNWidgets(2));
      final until = DateTime.now()
          .add(const Duration(days: 2))
          .toIso8601String();
      await tester.enterText(find.byType(TextFormField).at(0), until);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Turno revisado',
      );
      await tester.tap(find.text('Revisar cambio'));
      await tester.pumpAndSettle();
      expect(repo.granted, isNull);
      expect(find.textContaining('owner@example.test'), findsWidgets);
      await tester.tap(find.text('Confirmar cambio'));
      await tester.pumpAndSettle();
      expect(repo.granted!.take(4).toList(), [
        'a',
        'user-a',
        'drug.administer',
        'procedure-a',
      ]);
      expect(repo.granted!.last, 'Turno revisado');
    },
  );
  testWidgets('failed refresh removes stale management controls', (
    tester,
  ) async {
    final repo = PermissionFake();
    await mount(tester, repo);
    repo.fail = true;
    await tester.tap(find.text('Actualizar permisos'));
    await tester.pumpAndSettle();
    expect(find.text('Conceder permiso'), findsNothing);
    expect(find.textContaining('No se pudo consultar'), findsOneWidget);
  });
}
