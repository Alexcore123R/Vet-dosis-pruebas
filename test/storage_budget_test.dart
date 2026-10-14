import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/subscriptions/domain/storage_budget.dart';
import 'package:vetdosis_pro/modules/subscriptions/presentation/storage_budget_panel.dart';

void main() {
  test('Exact boundaries do not trigger early due to rounded percentage', () {
    for (final row in [
      (0, StorageLevel.normal),
      (7999, StorageLevel.normal),
      (8000, StorageLevel.warning),
      (9499, StorageLevel.warning),
      (9500, StorageLevel.critical),
      (9999, StorageLevel.critical),
      (10000, StorageLevel.full),
      (11000, StorageLevel.full),
    ]) {
      expect(StorageBudget.read('${row.$1}', 10000)!.level, row.$2);
    }
    expect(StorageBudget.read('7999', 10000)!.percent, '80.0');
    expect(StorageBudget.read('11000', 10000)!.fraction, 1);
    for (final pair in [
      (null, '100'),
      ('invalid', '100'),
      ('-1', '100'),
      ('1', '0'),
      ('1', '-1'),
    ]) {
      expect(StorageBudget.read(pair.$1, pair.$2), isNull);
    }
  });
  testWidgets(
    'Shows shared limit and no automatic billing; missing data stays unknown',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StorageBudgetPanel(
              used: '950',
              limit: '1000',
              personal: false,
            ),
          ),
        ),
      );
      expect(find.textContaining('95% del almacenamiento'), findsOneWidget);
      expect(find.textContaining('compartido'), findsOneWidget);
      expect(find.textContaining('No hay cobros automáticos'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StorageBudgetPanel(used: null, limit: '1000', personal: true),
          ),
        ),
      );
      expect(find.textContaining('no disponible'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
}
