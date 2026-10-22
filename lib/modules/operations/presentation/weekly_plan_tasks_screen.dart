import 'dart:convert';
import 'package:flutter/material.dart';
import '../../ai/domain/ai_repository.dart';
import '../../ai/presentation/request_ai_draft.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../core/presentation/unsaved_form_scope.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/operations_repository.dart';
import '../domain/weekly_task_draft.dart';

class WeeklyPlanTasksScreen extends StatefulWidget {
  const WeeklyPlanTasksScreen({
    super.key,
    required this.repository,
    required this.member,
    required this.week,
    required this.initialPlan,
    required this.people,
    required this.profile,
    required this.existing,
    this.ai,
  });
  final WeeklyTaskPlanRepository repository;
  final ClinicMembership member;
  final DateTime week;
  final String initialPlan;
  final Map<String, String> people;
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> existing;
  final AiRepository? ai;
  @override
  State<WeeklyPlanTasksScreen> createState() => _WeeklyPlanTasksScreenState();
}

class _WeeklyPlanTasksScreenState extends State<WeeklyPlanTasksScreen> {
  final exit = FormExitController();
  late final body = TextEditingController(text: widget.initialPlan);
  final tasks = <WeeklyTaskDraft>[];
  final selected = <int>{};
  bool busy = false, reviewed = false;
  String? error;
  String operation = newOperationId(), previous = '';
  int get capacity => int.tryParse('${widget.profile['daily_minutes']}') ?? 60;
  Map<String, dynamic> get availability =>
      Map<String, dynamic>.from(widget.profile['availability'] as Map? ?? {});
  List<WeeklyTaskDraft> get chosen => [
    for (var i = 0; i < tasks.length; i++)
      if (selected.contains(i)) tasks[i],
  ];
  List<String> get warnings => weeklyTaskWarnings(
    chosen,
    widget.existing,
    availability,
    capacity,
    widget.people,
  );
  @override
  void dispose() {
    body.dispose();
    exit.dispose();
    super.dispose();
  }

  Future<void> propose() async {
    if (widget.ai == null) return;
    if (body.text.trim().isEmpty) {
      setState(
        () => error =
            'Escribe o guarda primero el plan que quieres convertir en tareas.',
      );
      return;
    }
    final tokens = <String, String>{};
    for (final id in widget.people.keys) {
      tokens['persona_${tokens.length + 1}'] = id;
    }
    final loads = <String, int>{};
    for (final task in widget.existing) {
      final token = tokens.entries
          .where((e) => e.value == task['assigned_to'])
          .firstOrNull
          ?.key;
      if (token == null) continue;
      final key = '$token / ${task['scheduled_on']}';
      loads[key] =
          (loads[key] ?? 0) +
          (int.tryParse('${task['estimated_minutes']}') ?? 0);
    }
    final contextData = {
      'week_start': planningDate(widget.week),
      'week_end': planningDate(widget.week.add(const Duration(days: 6))),
      'daily_minutes_per_person': capacity,
      'team': {
        for (final token in tokens.entries)
          token.key: {
            'available_weekdays':
                availability[token.value] ?? [0, 1, 2, 3, 4, 5, 6],
          },
      },
      'already_assigned_minutes': loads,
      'plan': body.text.trim(),
    };
    if (jsonEncode(contextData).length > 16000) {
      setState(
        () => error =
            'Reduce el texto del plan antes de solicitar tareas. La propuesta no debe perder información al recortarse.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      final response = await requestAiDraft(
        context,
        repository: widget.ai!,
        member: widget.member,
        title: 'Proponer tareas de la semana',
        prompt:
            'Convierte este plan revisado en tareas operativas de una clínica: ${jsonEncode(contextData)}. '
            'Propón entre 1 y 40 tareas, únicamente dentro de la semana indicada. Usa los identificadores anónimos del equipo como assignee, o null si no hay una persona adecuada disponible. '
            'Los días disponibles van de 0=lunes a 6=domingo. Respeta el límite diario y la carga existente; distribuye el trabajo entre las personas disponibles. '
            'No agregues tareas que no deriven del plan ni supongas equipo, presupuesto o personal nuevos. No propongas tratamientos ni actos clínicos. '
            'Devuelve solo JSON válido: {"tasks":[{"title":"Tarea","scheduled_on":"AAAA-MM-DD","estimated_minutes":15,"assignee":"persona_1","area":"Recepción","instructions":"Pasos para revisar","priority":"media"}]}. '
            'Título máximo 150 caracteres, área 150, instrucciones 2000. Duración entera entre 1 y 480 minutos. Prioridad baja, media o urgente. El encargado revisará y elegirá qué tareas guardar.',
      );
      if (!mounted || response == null) return;
      final parsed = WeeklyTaskDraft.parseAi(response, widget.week, tokens);
      setState(() {
        tasks
          ..clear()
          ..addAll(parsed);
        selected
          ..clear()
          ..addAll(List.generate(tasks.length, (i) => i));
        reviewed = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se pudieron preparar las tareas. El plan no se modificó.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editTask([int? index]) async {
    if (index == null && tasks.length >= 40) {
      setState(() => error = 'La propuesta admite hasta 40 tareas.');
      return;
    }
    WeeklyTaskDraft? edited;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: index == null
              ? 'Agregar tarea a la propuesta'
              : 'Editar tarea propuesta',
          initial: index == null
              ? {
                  'scheduled_on': planningDate(widget.week),
                  'estimated_minutes': '15',
                  'priority': 'media',
                }
              : {
                  ...tasks[index].toMap(),
                  'estimated_minutes': '${tasks[index].minutes}',
                },
          fields: [
            const RxField('title', 'Tarea', required: true),
            const RxField(
              'scheduled_on',
              'Fecha',
              type: 'local_date',
              required: true,
            ),
            RxField(
              'assigned_to',
              'Responsable (vacío: sin asignar)',
              type: 'select',
              options: widget.people,
            ),
            const RxField(
              'estimated_minutes',
              'Duración en minutos',
              required: true,
            ),
            const RxField('area', 'Área'),
            const RxField('instructions', 'Instrucciones'),
            const RxField(
              'priority',
              'Prioridad',
              type: 'select',
              options: {'baja': 'Baja', 'media': 'Media', 'urgente': 'Urgente'},
              required: true,
            ),
          ],
          submit: (values, _) async {
            edited = WeeklyTaskDraft.fromMap(
              values,
              widget.week,
              widget.people.keys.toSet(),
            );
          },
        ),
      ),
    );
    if (saved != true || !mounted || edited == null) return;
    setState(() {
      if (index == null) {
        selected.add(tasks.length);
        tasks.add(edited!);
      } else {
        tasks[index] = edited!;
      }
      reviewed = false;
      error = null;
    });
  }

  Future<void> save() async {
    if (busy || !reviewed || chosen.isEmpty || warnings.isNotEmpty) return;
    if (body.text.trim().isEmpty) {
      setState(() => error = 'Escribe el plan que acompañará a las tareas.');
      return;
    }
    final values = chosen.map((t) => t.toMap()).toList();
    final fingerprint = jsonEncode({'body': body.text.trim(), 'tasks': values});
    if (previous.isNotEmpty && previous != fingerprint) {
      operation = newOperationId();
    }
    previous = fingerprint;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.commitWeekPlan(
        widget.member.clinicId,
        planningDate(widget.week),
        widget.initialPlan,
        body.text.trim(),
        values,
        operation,
      );
      if (mounted) exit.close(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se guardaron las tareas. Revisa permisos, cambios del equipo y SQL 14N antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: body.text != widget.initialPlan || tasks.isNotEmpty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Del plan a las tareas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Semana: ${planningDate(widget.week)} — ${planningDate(widget.week.add(const Duration(days: 6)))}',
          ),
          TextField(
            key: const ValueKey('weekly-plan-body'),
            controller: body,
            enabled: !busy,
            maxLength: 12000,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Plan que se convertirá en tareas',
            ),
            onChanged: (_) => setState(() => reviewed = false),
          ),
          Wrap(
            spacing: 8,
            children: [
              if (widget.ai != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : propose,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Proponer tareas con IA'),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => editTask(),
                icon: const Icon(Icons.add),
                label: const Text('Agregar tarea manual'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Text(
            '${chosen.length} tareas seleccionadas · ${chosen.fold<int>(0, (sum, t) => sum + t.minutes)} minutos en total',
          ),
          for (var i = 0; i < tasks.length; i++)
            Card(
              child: CheckboxListTile(
                key: ValueKey('weekly-task-$i'),
                value: selected.contains(i),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          selected.add(i);
                        } else {
                          selected.remove(i);
                        }
                        reviewed = false;
                      }),
                title: Text(tasks[i].title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tasks[i].day} · ${tasks[i].minutes} min · ${widget.people[tasks[i].assignee] ?? 'Sin asignar'}',
                    ),
                    if (tasks[i].area.isNotEmpty) Text(tasks[i].area),
                    if (tasks[i].instructions.isNotEmpty)
                      Text(tasks[i].instructions),
                    TextButton(
                      onPressed: busy ? null : () => editTask(i),
                      child: const Text(
                        'Editar fecha, responsable o instrucciones',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final warning in warnings)
            Text(
              warning,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (chosen.any((t) => t.assignee == null))
            const Text(
              'Hay tareas sin asignar. Podrás elegir responsables ahora o desde la semana después de guardarlas.',
            ),
          CheckboxListTile(
            title: const Text(
              'Revisé el plan y las tareas seleccionadas para esta semana',
            ),
            value: reviewed,
            onChanged: busy || chosen.isEmpty || warnings.isNotEmpty
                ? null
                : (v) => setState(() => reviewed = v == true),
          ),
          FilledButton(
            onPressed:
                busy || !reviewed || chosen.isEmpty || warnings.isNotEmpty
                ? null
                : save,
            child: const Text('Guardar plan y tareas seleccionadas'),
          ),
        ],
      ),
    ),
  );
}
