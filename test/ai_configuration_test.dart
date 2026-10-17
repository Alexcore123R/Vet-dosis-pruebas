import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/ai/presentation/ai_screen.dart';
import 'ai_plans_test.dart' show AiFake, personal;

class ConfigurationFake extends AiFake {
  String? revoked;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async => {
    'chats': [],
    'connections': [
      if (revoked == null)
        {'id': 'owned', 'provider': 'anthropic', 'scope': 'personal', 'can_manage': true},
      {'id': 'shared', 'provider': 'anthropic', 'scope': 'clinic', 'can_manage': false},
    ],
  };
  @override
  Future<void> disableKey(String connection) async { revoked = connection; }
}

void main() {
  testWidgets('Configuration shows only manageable keys and refreshes after revocation', (tester) async {
    final repository = ConfigurationFake();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: AiScreen(repository: repository, member: personal, configurationOnly: true),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Agregar proveedor / clave'), findsOneWidget);
    expect(find.text('Nuevo chat'), findsNothing);
    expect(find.text('Revocar clave'), findsOneWidget);
    await tester.tap(find.text('Revocar clave'));
    await tester.pumpAndSettle();
    expect(repository.revoked, 'owned');
    expect(find.text('Revocar clave'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Assistant keeps chat actions separate from credential administration', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: AiScreen(repository: AiFake(), member: personal),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo chat'), findsOneWidget);
    expect(find.text('Agregar proveedor / clave'), findsNothing);
    expect(find.text('Revocar clave'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
