import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/operations/domain/operations_repository.dart';
import 'package:vetdosis_pro/modules/operations/presentation/weekly_plan_tasks_screen.dart';
import 'productivity_test.dart' show member;

class BatchFake implements WeeklyTaskPlanRepository {
  final operations = <String>[];
  final batches = <List<Map<String, dynamic>>>[];
  @override
  Future<void> commitWeekPlan(
    String clinic,
    String week,
    String expected,
    String body,
    List<Map<String, dynamic>> tasks,
    String operation,
  ) async {
    operations.add(operation);
    batches.add(tasks);
    throw const FormatException('Prueba de reintento');
  }
}

void main() {
  testWidgets(
    'manual proposal stays local until reviewed and retries keep the operation',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = BatchFake();
      await tester.pumpWidget(
        MaterialApp(
          home: WeeklyPlanTasksScreen(
            repository: repo,
            member: member,
            week: DateTime(2026, 11, 2),
            initialPlan: 'Ordenar recepción',
            people: const {},
            profile: const {},
            existing: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar tarea manual'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Ordenar escritorio',
      );
      final save = find.widgetWithText(FilledButton, 'Guardar');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.operations, isEmpty);
      final commit = find.widgetWithText(
        FilledButton,
        'Guardar plan y tareas seleccionadas',
      );
      expect(tester.widget<FilledButton>(commit).onPressed, isNull);
      await tester.tap(
        find.text('Revisé el plan y las tareas seleccionadas para esta semana'),
      );
      await tester.pumpAndSettle();
      await tester.tap(commit);
      await tester.pumpAndSettle();
      await tester.ensureVisible(commit);
      await tester.pumpAndSettle();
      await tester.tap(commit);
      await tester.pumpAndSettle();
      expect(repo.operations.length, 2);
      expect(repo.operations.first, repo.operations.last);

      expect(repo.batches.first.single['title'], 'Ordenar escritorio');
      expect(repo.batches.first.single['assigned_to'], isNull);
    },
  );
}
