import '../../ai/domain/assisted_drafts.dart';

String planningDate(DateTime day) => day.toIso8601String().substring(0, 10);

class WeeklyTaskDraft {
  const WeeklyTaskDraft({
    required this.title,
    required this.day,
    required this.minutes,
    this.assignee,
    this.area = '',
    this.instructions = '',
    this.priority = 'media',
  });
  final String title, day, area, instructions, priority;
  final String? assignee;
  final int minutes;
  Map<String, dynamic> toMap() => {
    'title': title,
    'scheduled_on': day,
    'estimated_minutes': minutes,
    'assigned_to': assignee,
    'area': area,
    'instructions': instructions,
    'priority': priority,
  };
  static WeeklyTaskDraft fromMap(
    Map<String, dynamic> raw,
    DateTime week,
    Set<String> members,
  ) {
    final title = draftText(raw['title'], 150);
    final day = raw['scheduled_on'];
    final parsed = day is String ? DateTime.tryParse(day) : null;
    if (parsed == null ||
        planningDate(parsed) != day ||
        parsed.isBefore(week) ||
        parsed.isAfter(week.add(const Duration(days: 6)))) {
      throw const FormatException(
        'La fecha debe pertenecer a la semana seleccionada.',
      );
    }
    final minutes = int.tryParse('${raw['estimated_minutes']}');
    if (minutes == null || minutes < 1 || minutes > 480) {
      throw const FormatException('Indica una duración entre 1 y 480 minutos.');
    }
    final who = raw['assigned_to'];
    if (who != null &&
        who != '' &&
        (who is! String || !members.contains(who))) {
      throw const FormatException(
        'El responsable no pertenece al equipo disponible.',
      );
    }
    final area = raw['area'] ?? '',
        instructions = raw['instructions'] ?? '',
        priority = raw['priority'] ?? 'media';
    if (area is! String ||
        area.length > 150 ||
        instructions is! String ||
        instructions.length > 2000 ||
        !['baja', 'media', 'urgente'].contains(priority)) {
      throw const FormatException(
        'Revisa el área, las instrucciones y la prioridad de la tarea.',
      );
    }
    return WeeklyTaskDraft(
      title: title,
      day: day as String,
      minutes: minutes,
      assignee: who == '' ? null : who as String?,
      area: area.trim(),
      instructions: instructions.trim(),
      priority: priority as String,
    );
  }

  static List<WeeklyTaskDraft> parseAi(
    String response,
    DateTime week,
    Map<String, String> tokens,
  ) {
    final rows = readDraftObject(response)['tasks'];
    if (rows is! List || rows.isEmpty || rows.length > 40) {
      throw const FormatException(
        'La propuesta debe contener entre 1 y 40 tareas.',
      );
    }
    return rows.map((row) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException(
          'La propuesta contiene una tarea no válida.',
        );
      }
      final token = row['assignee'];
      if (token != null &&
          token != '' &&
          (token is! String || !tokens.containsKey(token))) {
        throw const FormatException(
          'La IA propuso un responsable que no está en el equipo.',
        );
      }
      return fromMap(
        {
          ...row,
          'assigned_to': token == null || token == '' ? null : tokens[token],
        },
        week,
        tokens.values.toSet(),
      );
    }).toList();
  }
}

List<String> weeklyTaskWarnings(
  List<WeeklyTaskDraft> proposed,
  List<Map<String, dynamic>> existing,
  Map<String, dynamic> availability,
  int dailyMinutes,
  Map<String, String> names,
) {
  final warnings = <String>[], load = <String, int>{}, seen = <String>{};
  String identity(String title, String day, String? who, String area) =>
      '$day|$who|${title.trim().toLowerCase()}|${area.trim()}';
  for (final task in existing) {
    final who = task['assigned_to'];
    final key = '${task['scheduled_on']}|$who';
    load[key] =
        (load[key] ?? 0) + (int.tryParse('${task['estimated_minutes']}') ?? 0);
    seen.add(
      identity(
        '${task['title']}',
        '${task['scheduled_on']}',
        who as String?,
        '${task['area'] ?? ''}',
      ),
    );
  }
  for (final task in proposed) {
    if (!seen.add(identity(task.title, task.day, task.assignee, task.area))) {
      warnings.add('Ya existe o se repite: ${task.title} (${task.day}).');
    }
    if (task.assignee == null) continue;
    final days = availability[task.assignee] as List?;
    final weekday = DateTime.parse(task.day).weekday - 1;
    final name = names[task.assignee] ?? 'Integrante';
    if (days != null && !days.contains(weekday)) {
      warnings.add('$name no está disponible el ${task.day}.');
    }
    final key = '${task.day}|${task.assignee}';
    load[key] = (load[key] ?? 0) + task.minutes;
    if (load[key]! > dailyMinutes) {
      warnings.add('$name supera $dailyMinutes minutos el ${task.day}.');
    }
  }
  return warnings.toSet().toList();
}
