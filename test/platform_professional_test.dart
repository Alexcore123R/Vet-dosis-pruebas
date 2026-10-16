import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/beta/domain/beta_repository.dart';
import 'package:vetdosis_pro/modules/beta/presentation/platform_professional_screen.dart';

class ProfessionalFake implements PlatformProfessionalRepository {
  bool fail = false, revoked = false;
  List<String>? lastRevocation;
  @override
  Future<List<Map<String, dynamic>>> globalProfessionalReviews() async {
    if (fail) throw StateError('denied');
    return [
      {
        'id': 'review-a',
        'name': 'Profesional de prueba',
        'license': 'TEST-ONLY',
        'email': 'synthetic@example.test',
        'reviewer_id': 'reviewer-a',
        'reviewed_at': '2026-10-15T10:00:00Z',
        'valid_until': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'evidence_hash': 'synthetic-hash',
        'evidence_reference': 'Referencia privada de prueba',
        'revoked': revoked,
      },
    ];
  }

  @override
  Future<void> revokeGlobalProfessionalReview(String id, String reason) async {
    lastRevocation = [id, reason];
    revoked = true;
  }
}

Future<void> mount(WidgetTester tester, ProfessionalFake repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: PlatformProfessionalScreen(repository: repo)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Global review fits phone and does not create professional verifications',
    (tester) async {
      await mount(tester, ProfessionalFake());
      expect(find.textContaining('fuera de la app'), findsOneWidget);
      expect(find.textContaining('TEST-ONLY'), findsOneWidget);
      expect(find.text('Registrar verificación'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Revocation requires a reason and explicit confirmation', (
    tester,
  ) async {
    final repo = ProfessionalFake();
    await mount(tester, repo);
    await tester.tap(find.text('Revocar verificación global'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar revocación'));
    await tester.pumpAndSettle();
    expect(find.text('Indica el motivo'), findsOneWidget);
    expect(repo.lastRevocation, isNull);
    await tester.enterText(find.byType(TextFormField), 'Evidencia retirada');
    await tester.tap(find.text('Confirmar revocación'));
    await tester.pumpAndSettle();
    expect(repo.lastRevocation, ['review-a', 'Evidencia retirada']);
    expect(find.text('Revocada'), findsOneWidget);
    expect(find.text('Revocar verificación global'), findsNothing);
  });
  testWidgets('Failed refresh clears private evidence from screen', (
    tester,
  ) async {
    final repo = ProfessionalFake();
    await mount(tester, repo);
    repo.fail = true;
    await tester.tap(find.text('Actualizar habilitaciones'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TEST-ONLY'), findsNothing);
    expect(find.textContaining('No se pudo consultar'), findsOneWidget);
    expect(find.text('Revocar verificación global'), findsNothing);
  });
}
