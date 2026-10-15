import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/beta/domain/beta_repository.dart';
import 'package:vetdosis_pro/modules/beta/presentation/beta_boundary.dart';

class BetaFake implements BetaRepository {
  BetaState current = const BetaState({
    'mode': 'not_enrolled',
    'admissions_enabled': false,
  });
  int enrollments = 0;
  bool offline = false;
  @override
  Future<BetaState> status(String? clinic) async {
    if (offline) throw StateError('offline');
    return current;
  }

  @override
  Future<void> enroll(String version, String hash, String? token) async {
    enrollments++;
    current = const BetaState({'mode': 'active'});
  }

  @override
  Future<void> sponsor(String id) async {}
  @override
  Future<Map<String, dynamic>> administration() async => {};
  @override
  Future<BetaMfaSetup> prepareMfa() async =>
      const BetaMfaSetup('synthetic-factor');
  @override
  Future<void> verifyMfa(String id, String code) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'La conexión fallida bloquea acceso sin perder el borrador de la pantalla',
    (tester) async {
      final repository = BetaFake()
        ..current = const BetaState({'mode': 'active'});
      await tester.pumpWidget(
        MaterialApp(
          home: BetaBoundary(
            repository: repository,
            onSignOut: () async {},
            onRefresh: () async {},
            child: const Scaffold(
              body: TextField(
                decoration: InputDecoration(labelText: 'Borrador'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Texto aún sin guardar');
      repository.offline = true;
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(find.textContaining('No se pudo verificar'), findsOneWidget);
      expect(find.text('Texto aún sin guardar'), findsNothing);
      repository.offline = false;
      await tester.tap(find.text('Revisar acceso'));
      await tester.pumpAndSettle();
      expect(find.text('Texto aún sin guardar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  Widget app(BetaFake repository) => MaterialApp(
    home: BetaBoundary(
      repository: repository,
      onSignOut: () async {},
      onRefresh: () async {},
      child: const Scaffold(body: Text('Workspace sintético')),
    ),
  );
  testWidgets(
    'Admisiones cerradas no exponen el espacio ni permiten aceptar términos',
    (tester) async {
      final repository = BetaFake();
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(find.text('Workspace sintético'), findsNothing);
      expect(
        find.textContaining('admisiones beta todavía están cerradas'),
        findsOneWidget,
      );
      expect(find.text('Ingresar a la beta'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'No se inscribe hasta aceptar la versión publicada de los términos',
    (tester) async {
      final repository = BetaFake()
        ..current = const BetaState({
          'mode': 'not_enrolled',
          'admissions_enabled': true,
          'terms': {
            'version': 'test',
            'hash': 'synthetic',
            'content': 'Términos ficticios de prueba',
          },
        });
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Ingresar a la beta'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ingresar a la beta'));
      await tester.pumpAndSettle();
      expect(repository.enrollments, 1);
      expect(find.text('Workspace sintético'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Vencimiento permite consulta/exportación y avisa actualización',
    (tester) async {
      final repository = BetaFake()
        ..current = const BetaState({
          'mode': 'read_export',
          'update_required': true,
        });
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(find.text('Workspace sintético'), findsOneWidget);
      expect(find.textContaining('requiere actualización'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Cuenta de plataforma no muestra herramientas administrativas antes del 2FA',
    (tester) async {
      final repository = BetaFake()
        ..current = const BetaState({
          'mode': 'platform_admin',
          'mfa_ready': false,
        });
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(find.text('Preparar 2FA'), findsOneWidget);
      expect(find.text('Aprobar correo'), findsNothing);
      expect(find.text('Workspace sintético'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Cuenta de plataforma con aal2 tiene panel móvil y no espacio clínico',
    (tester) async {
      final repository = BetaFake()
        ..current = const BetaState({
          'mode': 'platform_admin',
          'mfa_ready': true,
        });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(find.text('Aprobar correo'), findsOneWidget);
      expect(find.text('Workspace sintético'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
