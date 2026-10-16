import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/beta/domain/beta_repository.dart';
import 'package:vetdosis_pro/modules/beta/presentation/beta_boundary.dart';

class BetaFake implements BetaRepository {
  BetaState current = const BetaState({
    'mode': 'not_enrolled',
    'admissions_enabled': false,
  });
  int enrollments = 0, acceptances = 0;
  String? acceptedVersion, acceptedHash, enrolledVersion, enrolledHash;
  bool replaceTermsOnAcceptance = false;
  bool offline = false;
  @override
  Future<BetaState> status(String? clinic) async {
    if (offline) throw StateError('offline');
    return current;
  }

  @override
  Future<void> enroll(String version, String hash, String? token) async {
    enrollments++;
    enrolledVersion = version;
    enrolledHash = hash;
    current = const BetaState({'mode': 'active'});
  }

  @override
  Future<void> acceptTerms(String version, String hash) async {
    if (replaceTermsOnAcceptance) {
      current = BetaState({
        ...current.data,
        'terms': {'version': '2', 'hash': 'hash-2', 'content': 'Texto segundo'},
      });
      throw StateError('beta_terms_changed');
    }
    acceptances++;
    acceptedVersion = version;
    acceptedHash = hash;
    current = BetaState({...current.data, 'terms_acceptance_required': false});
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
      expect(repository.enrolledVersion, 'test');
      expect(repository.enrolledHash, 'synthetic');
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
  BetaFake pendingTerms() => BetaFake()
    ..current = const BetaState({
      'mode': 'active',
      'terms_acceptance_required': true,
      'terms': {'version': '1', 'hash': 'hash-1', 'content': 'Texto primero'},
    });
  testWidgets('La versión visible es la enviada al aceptar actualización', (
    tester,
  ) async {
    final repository = pendingTerms();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Términos de uso · versión 1'), findsOneWidget);
    expect(find.text('Texto primero'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Aceptar versión 1'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar versión 1'));
    await tester.pumpAndSettle();
    expect(repository.acceptedVersion, '1');
    expect(repository.acceptedHash, 'hash-1');
    expect(repository.enrollments, 0);
    expect(find.text('Workspace sintético'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Puede consultar y exportar sin aceptar ni renovar la beta', (
    tester,
  ) async {
    final repository = pendingTerms();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar solo consulta y exportación'));
    await tester.pumpAndSettle();
    expect(find.text('Workspace sintético'), findsOneWidget);
    expect(find.textContaining('Términos pendientes'), findsOneWidget);
    expect(repository.acceptances, 0);
    expect(repository.enrollments, 0);
    await tester.tap(find.text('Leer y aceptar términos actualizados'));
    await tester.pumpAndSettle();
    expect(find.text('Texto primero'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Cambiar número de versión con mismo hash quita la selección', (
    tester,
  ) async {
    final repository = pendingTerms();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    repository.current = const BetaState({
      'mode': 'active',
      'terms_acceptance_required': true,
      'terms': {'version': '2', 'hash': 'hash-1', 'content': 'Texto primero'},
    });
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Términos de uso · versión 2'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Aceptar versión 2'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Si servidor cambió texto, carga versión actual y exige aceptarla',
    (tester) async {
      final repository = pendingTerms()..replaceTermsOnAcceptance = true;
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar versión 1'));
      await tester.pumpAndSettle();
      expect(find.text('Texto segundo'), findsOneWidget);
      expect(find.textContaining('Los términos cambiaron'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      expect(repository.acceptances, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Aceptar términos conserva el borrador sin refrescar membresías',
    (tester) async {
      final repository = BetaFake()
        ..current = const BetaState({'mode': 'active'});
      var membershipRefreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BetaBoundary(
            repository: repository,
            onSignOut: () async {},
            onRefresh: () async {
              membershipRefreshes++;
            },
            child: const Scaffold(
              body: TextField(
                decoration: InputDecoration(labelText: 'Captura en curso'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Borrador intacto');
      repository.current = pendingTerms().current;
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar versión 1'));
      await tester.pumpAndSettle();
      expect(find.text('Borrador intacto'), findsOneWidget);
      expect(membershipRefreshes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
