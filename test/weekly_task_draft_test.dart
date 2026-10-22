import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/operations/domain/weekly_task_draft.dart';

void main() {
  final week = DateTime(2026, 11, 2);
  final task = <String, dynamic>{
    'title': 'Limpiar recepción',
    'scheduled_on': '2026-11-02',
    'estimated_minutes': 15,
    'assignee': 'persona_1',
  };
  test('AI tokens resolve only to known members and valid week dates', () {
    final parsed = WeeklyTaskDraft.parseAi(
      jsonEncode({
        'tasks': [task],
      }),
      week,
      {'persona_1': 'member'},
    );
    expect(parsed.single.assignee, 'member');
    expect(parsed.single.toMap()['estimated_minutes'], 15);
    for (final invalid in [
      {...task, 'assignee': 'unknown'},
      {...task, 'scheduled_on': '2026-11-09'},
      {...task, 'estimated_minutes': 0},
      {...task, 'scheduled_on': '2026-11-31'},
    ]) {
      expect(
        () => WeeklyTaskDraft.parseAi(
          jsonEncode({
            'tasks': [invalid],
          }),
          week,
          {'persona_1': 'member'},
        ),
        throwsFormatException,
      );
    }
  });
  test('review includes existing load, availability and duplicate tasks', () {
    const draft = WeeklyTaskDraft(
      title: 'Limpiar',
      day: '2026-11-02',
      minutes: 20,
      assignee: 'member',
    );
    final warnings = weeklyTaskWarnings(
      [draft, draft],
      [
        {
          'title': 'Otra',
          'scheduled_on': '2026-11-02',
          'estimated_minutes': 15,
          'assigned_to': 'member',
        },
      ],
      {
        'member': [1],
      },
      30,
      {'member': 'Ana'},
    );
    expect(warnings.any((w) => w.contains('supera')), isTrue);
    expect(warnings.any((w) => w.contains('no está disponible')), isTrue);
    expect(warnings.any((w) => w.contains('se repite')), isTrue);
  });
  test(
    'unassigned tasks remain available for review without assigning someone',
    () {
      const draft = WeeklyTaskDraft(
        title: 'Ordenar',
        day: '2026-11-02',
        minutes: 20,
      );
      expect(weeklyTaskWarnings([draft], [], {}, 30, {}), isEmpty);
      expect(draft.toMap()['assigned_to'], isNull);
    },
  );
}
