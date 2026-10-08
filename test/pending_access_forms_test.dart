import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/auth_repository.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'support/fake_auth.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_screen.dart';

class RecoveryFake extends FakeAuth implements PasswordRecoveryRepository {
  @override
  bool recoveringPassword = false;
  int requests = 0, updates = 0;
  @override
  Future<void> requestPasswordRecovery(String email) async {
    requests++;
  }

  @override
  Future<void> completePasswordRecovery(String password) async {
    updates++;
    recoveringPassword = false;
  }
}

void main() {
  testWidgets(
    'Recovery link displays password confirmation even with clinic access',
    (tester) async {
      final repo = RecoveryFake()..recoveringPassword = true;
      final model = AuthViewModel(repo);
      await model.start();
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: model,
            builder: (_, _) => AuthScreen(model: model),
          ),
        ),
      );
      expect(find.text('Actualizar contraseña'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'new-password');
      await tester.enterText(find.byType(TextFormField).at(1), 'different');
      await tester.tap(find.text('Actualizar contraseña'));
      await tester.pumpAndSettle();
      expect(repo.updates, 0);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), 'new-password');
      await tester.tap(find.text('Actualizar contraseña'));
      await tester.pumpAndSettle();
      expect(repo.updates, 1);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      await repo.controller.close();
    },
  );

  test(
    'Recovery requires a valid email and an actual recovery session',
    () async {
      final repo = RecoveryFake();
      final model = AuthViewModel(repo);
      await model.requestPasswordRecovery('invalid');
      expect(repo.requests, 0);
      await model.requestPasswordRecovery('someone@example.test');
      expect(repo.requests, 1);
      expect(model.message, contains('Si existe una cuenta'));
      await model.completePasswordRecovery('long-password');
      expect(repo.updates, 0);
      repo.recoveringPassword = true;
      await model.completePasswordRecovery('short');
      expect(repo.updates, 0);
      await model.completePasswordRecovery('long-password');
      expect(repo.updates, 1);
      expect(model.recoveringPassword, false);
      model.dispose();
      await repo.controller.close();
    },
  );

  testWidgets('Back keeps unsaved data unless explicitly discarded', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => RxEntryScreen(
                    title: 'Formulario',
                    fields: const [RxField('note', 'Nota')],
                    submit: (_, _) async {},
                  ),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Dato pendiente');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('Dato pendiente'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir sin guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
  });
}
