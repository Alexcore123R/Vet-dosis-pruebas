import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'support/fake_auth.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';

void main() {
  late FakeAuth repo;
  late AuthViewModel model;
  setUp(() {
    repo = FakeAuth();
    model = AuthViewModel(repo);
  });
  tearDown(() async {
    model.dispose();
    await repo.controller.close();
  });
  test(
    'El rol viene del servidor; auxiliar no puede generar invitación',
    () async {
      await model.start();
      expect(model.active?.role, ClinicRole.auxiliar);
      await model.invite('member@example.test', ClinicRole.admin);
      expect(repo.inviteCalls, 0);
      expect(model.error, isNotNull);
    },
  );
  test('Fallo de acceso elimina la clínica anterior', () async {
    await model.start();
    repo.failRead = true;
    await model.refresh();
    expect(model.active, isNull);
    expect(model.memberships, isEmpty);
    expect(model.error, isNotNull);
  });
  test('Lectura antigua no restaura acceso después de cerrar sesión', () async {
    await model.start();
    repo.pending = Completer<List<ClinicMembership>>();
    final oldRead = model.refresh();
    final pending = repo.pending!;
    repo.pending = null;
    await model.signOut();
    pending.complete([member]);
    await oldRead;
    expect(model.signedIn, isFalse);
    expect(model.active, isNull);
  });
  test('Rol desconocido falla sin sustituir por admin', () {
    expect(() => ClinicRole.parse('superuser'), throwsFormatException);
  });
  testWidgets(
    'Sin conexión configurada no aparece la clínica ni roles elegibles',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        VetDosisApp(
          model: CoreViewModel(SettingsRepository(), const AppSettings()),
          requireAuth: true,
        ),
      );
      expect(find.text('Bienvenido'), findsOneWidget);
      expect(find.text('Cálculo rápido'), findsNothing);
      expect(find.byType(DropdownButtonFormField<ClinicRole>), findsNothing);
    },
  );
  testWidgets('Login valida datos antes de enviar', (tester) async {
    repo.userId = null;
    await model.start();
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      VetDosisApp(
        model: CoreViewModel(SettingsRepository(), const AppSettings()),
        auth: model,
        requireAuth: true,
      ),
    );
    expect(find.text('Continuar con Google'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Iniciar sesión'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa un correo válido'), findsOneWidget);
    expect(model.signedIn, isFalse);
    expect(tester.takeException(), isNull);
  });
}
