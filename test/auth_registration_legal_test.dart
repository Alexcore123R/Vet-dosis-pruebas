import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/auth_repository.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_screen.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';

class FakePublishedLegalAuth implements AuthRepository, RegistrationLegalRepository {
  RegistrationLegal? legal = RegistrationLegal(
    terms: RegistrationLegalDocument(
      version: '1',
      hash: List.filled(64, 'a').join(),
      content: 'Términos de uso ficticios, exclusivamente para pruebas.',
    ),
    privacy: RegistrationLegalDocument(
      version: '2',
      hash: List.filled(64, 'b').join(),
      content: 'Aviso de privacidad ficticio, exclusivamente para pruebas.',
    ),
  );
  bool changeOnSecondRead = false;
  int legalReads = 0;
  int registrations = 0;

  @override
  String? get userId => null;
  @override
  Stream<void> get changes => const Stream<void>.empty();
  @override
  Future<RegistrationLegal?> registrationLegal() async {
    legalReads++;
    if (changeOnSecondRead && legalReads > 1) {
      return RegistrationLegal(
        terms: RegistrationLegalDocument(
          version: '3',
          hash: List.filled(64, 'c').join(),
          content: 'Versión nueva y ficticia de términos.',
        ),
        privacy: legal!.privacy,
      );
    }
    return legal;
  }

  @override
  Future<void> register(String email, String password) async {
    registrations++;
  }

  @override
  Future<List<ClinicMembership>> memberships() async => [];
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> googleSignIn() async {}
  @override
  Future<void> createClinic(String name) async {}
  @override
  Future<void> joinClinic(String token) async {}
  @override
  Future<String> invite(String clinicId, String email, ClinicRole role) async => 'synthetic';
}

void main() {
  test('Acepta documentos publicados solo si hash corresponde a bytes exactos', () {
    const termsText = 'Términos clínicos de prueba';
    const privacyText = 'Aviso de privacidad de prueba';
    final parsed = RegistrationLegal.fromJson({
      'terms': {
        'version': 'terms-test',
        'hash': sha256.convert(utf8.encode(termsText)).toString(),
        'content': termsText,
      },
      'privacy': {
        'version': 'notice-test',
        'hash': sha256.convert(utf8.encode(privacyText)).toString(),
        'content': privacyText,
      },
    });
    expect(parsed.terms.content, termsText);
    expect(parsed.privacy.content, privacyText);
  });

  test('Bloquea texto manipulado aunque hash tenga formato SHA-256', () {
    expect(
      () => RegistrationLegalDocument.fromJson({
        'version': '1',
        'content': 'Contenido modificado',
        'hash': sha256.convert(utf8.encode('Contenido original')).toString(),
      }),
      throwsFormatException,
    );
  });

  test('No se admite documento publicado sin hash y texto completo', () {
    expect(
      () => RegistrationLegal.fromJson({
        'terms': {
          'version': '1',
          'hash': 'incorrecto',
          'content': 'algo',
        },
        'privacy': {
          'version': '1',
          'hash': List.filled(64, 'b').join(),
          'content': 'algo',
        },
      }),
      throwsFormatException,
    );
  });

  Future<void> openSignup(WidgetTester tester, FakePublishedLegalAuth repository) async {
    final model = AuthViewModel(repository);
    addTearDown(model.dispose);
    await model.start();
    await tester.pumpWidget(MaterialApp(home: AuthScreen(model: model)));
    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'usuario@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'contrasena-ficticia-123');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();
  }

  testWidgets('Sin publicación legal, no permite crear cuenta', (tester) async {
    final repository = FakePublishedLegalAuth()..legal = null;
    await openSignup(tester, repository);
    expect(repository.registrations, 0);
    expect(find.textContaining('no hay términos y aviso de privacidad publicados'), findsOneWidget);
  });

  testWidgets('Dos casillas obligatorias y cancelar no registra cuenta', (tester) async {
    final repository = FakePublishedLegalAuth();
    await openSignup(tester, repository);
    expect(find.text('Antes de crear tu cuenta'), findsOneWidget);
    final accept = find.widgetWithText(FilledButton, 'Aceptar y crear cuenta');
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);

    await tester.ensureVisible(find.byKey(const Key('signup-privacy-checkbox')));
    await tester.tap(find.byKey(const Key('signup-privacy-checkbox')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);

    await tester.ensureVisible(find.byKey(const Key('signup-terms-checkbox')));
    await tester.tap(find.byKey(const Key('signup-terms-checkbox')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repository.registrations, 0);
  });

  testWidgets('Rechaza la versión antigua si se publica una nueva', (tester) async {
    final repository = FakePublishedLegalAuth()..changeOnSecondRead = true;
    await openSignup(tester, repository);
    await tester.ensureVisible(find.byKey(const Key('signup-privacy-checkbox')));
    await tester.tap(find.byKey(const Key('signup-privacy-checkbox')));
    await tester.ensureVisible(find.byKey(const Key('signup-terms-checkbox')));
    await tester.tap(find.byKey(const Key('signup-terms-checkbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar y crear cuenta'));
    await tester.pumpAndSettle();
    expect(repository.registrations, 0);
    expect(find.textContaining('cambiaron'), findsOneWidget);
  });

  testWidgets('Solicita alta solo después de aceptar textos publicados vigentes', (tester) async {
    final repository = FakePublishedLegalAuth();
    await openSignup(tester, repository);
    await tester.ensureVisible(find.byKey(const Key('signup-privacy-checkbox')));
    await tester.tap(find.byKey(const Key('signup-privacy-checkbox')));
    await tester.ensureVisible(find.byKey(const Key('signup-terms-checkbox')));
    await tester.tap(find.byKey(const Key('signup-terms-checkbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar y crear cuenta'));
    await tester.pumpAndSettle();
    expect(repository.registrations, 1);
    expect(repository.legalReads, 2);
  });
}
