import '../../core/presentation/unsaved_form_scope.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../patients/domain/patient_models.dart';
import '../../patients/presentation/patient_view_model.dart';
import '../domain/hospital_models.dart';

class HospitalAdmitForm extends StatefulWidget {
  const HospitalAdmitForm({
    super.key,
    required this.patients,
    required this.save,
    this.optionalCage = false,
  });
  final bool optionalCage;
  final List<VetPatient> patients;
  final Future<bool> Function(String, String, String) save;
  @override
  State<HospitalAdmitForm> createState() => _HospitalAdmitFormState();
}

class _HospitalAdmitFormState extends State<HospitalAdmitForm> {
  final exit = FormExitController();
  bool get dirty => patientId != null || cage.text.isNotEmpty;
  @override
  void initState() {
    super.initState();
    cage.addListener(() {
      if (mounted) setState(() {});
    });
  }

  String? patientId, error, attempted;
  String operationId = newOperationId();
  final cage = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    exit.dispose();
    cage.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (patientId == null) {
        throw const FormatException('Selecciona el paciente.');
      }
      final label = hospitalText(
        cage.text,
        max: 80,
        allowEmpty: widget.optionalCage,
      );
      final fp = jsonEncode([patientId, label]);
      if (attempted != null && attempted != fp) operationId = newOperationId();
      attempted = fp;
      final ok = await widget.save(patientId!, label, operationId);
      if (!mounted) return;
      if (ok) {
        exit.close(context);
        return;
      }
      setState(
        () => error =
            'No se pudo ingresar. Revisa si ya está hospitalizado o si la jaula está ocupada.',
      );
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: dirty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Ingresar a hospitalización')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.patients.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'No hay pacientes disponibles para ingresar. '
                'Registra un paciente y actualiza hospitalización.',
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: patientId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paciente'),
            items: widget.patients
                .map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text('${p.name} · ${p.species}'),
                  ),
                )
                .toList(),
            onChanged: busy ? null : (v) => setState(() => patientId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: cage,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: widget.optionalCage
                  ? 'Jaula / box (opcional)'
                  : 'Jaula / box',
              helperText: widget.optionalCage
                  ? 'Puedes asignarla o cambiarla después.'
                  : null,
              border: OutlineInputBorder(),
            ),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy || widget.patients.isEmpty ? null : save,
            child: const Text('Registrar ingreso'),
          ),
        ],
      ),
    ),
  );
}

class HospitalOrderForm extends StatefulWidget {
  const HospitalOrderForm({
    super.key,
    required this.stay,
    required this.save,
    this.reviewTypes,
    this.initialLabel,
    this.initialInstructions,
  });
  final List<HospitalReviewType>? reviewTypes;
  final String? initialLabel, initialInstructions;
  final HospitalStay stay;
  final Future<bool> Function(
    String,
    String,
    String,
    List<DateTime>,
    int,
    String,
  )
  save;
  @override
  State<HospitalOrderForm> createState() => _HospitalOrderFormState();
}

class _HospitalOrderFormState extends State<HospitalOrderForm> {
  final exit = FormExitController();
  bool get dirty =>
      label.text.isNotEmpty ||
      instructions.text.isNotEmpty ||
      delay.text.isNotEmpty ||
      times.isNotEmpty ||
      reviewed ||
      kind != (widget.reviewTypes == null ? 'medicacion' : '');
  @override
  void initState() {
    super.initState();
    if (widget.reviewTypes != null) kind = '';
    label.text = widget.initialLabel ?? '';
    instructions.text = widget.initialInstructions ?? '';
    for (final c in [label, instructions, delay]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  final label = TextEditingController(),
      instructions = TextEditingController(),
      delay = TextEditingController();
  String kind = 'medicacion', operationId = newOperationId();
  String? error, attempted;
  final times = <DateTime>[];
  bool reviewed = false, busy = false;
  @override
  void dispose() {
    exit.dispose();
    label.dispose();
    instructions.dispose();
    delay.dispose();
    super.dispose();
  }

  Future<void> addTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    final instant = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    try {
      validateSchedule([...times, instant], now: DateTime.now());
      setState(() {
        times.add(instant);
        times.sort();
        reviewed = false;
        error = null;
      });
    } on FormatException catch (e) {
      setState(() => error = e.message.toString());
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (!reviewed) {
        throw const FormatException(
          'Revisa la indicación y los horarios del paciente.',
        );
      }
      if (widget.reviewTypes != null &&
          !widget.reviewTypes!.any((t) => t.id == kind)) {
        throw const FormatException('Selecciona el tipo de procedimiento.');
      }
      final name = hospitalText(label.text),
          order = hospitalText(instructions.text, max: 4000);
      final escalation = int.tryParse(delay.text.trim());
      if (escalation == null || escalation < 1 || escalation > 120) {
        throw const FormatException(
          'Indica entre 1 y 120 minutos para el aviso de retraso.',
        );
      }
      final schedule = validateSchedule(times, now: DateTime.now());
      final fp = jsonEncode([
        kind,
        name,
        order,
        schedule.map((t) => t.toIso8601String()).toList(),
        escalation,
      ]);
      if (attempted != null && attempted != fp) operationId = newOperationId();
      attempted = fp;
      final ok = await widget.save(
        kind,
        name,
        order,
        schedule,
        escalation,
        operationId,
      );
      if (!mounted) return;
      if (ok) {
        exit.close(context);
        return;
      }
      setState(
        () => error =
            'No se pudo guardar. Actualiza la hoja antes de modificar o repetir la orden.',
      );
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: dirty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.reviewTypes == null
              ? 'Indicar tratamiento / revisión'
              : 'Programar revisión',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('${widget.stay.patientName} · Jaula ${widget.stay.cageLabel}'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: kind.isEmpty ? null : kind,
            decoration: InputDecoration(
              labelText: widget.reviewTypes == null
                  ? 'Tipo'
                  : 'Tipo de procedimiento',
            ),
            items:
                widget.reviewTypes
                    ?.map(
                      (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                    )
                    .toList() ??
                const [
                  DropdownMenuItem(
                    value: 'medicacion',
                    child: Text('Medicación'),
                  ),
                  DropdownMenuItem(value: 'revision', child: Text('Revisión')),
                ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    kind = v ?? kind;
                    reviewed = false;
                  }),
          ),
          if (widget.reviewTypes?.isEmpty == true)
            const Text(
              'No hay tipos activos. Solicita su configuración; no se asignan automáticamente.',
            ),
          const SizedBox(height: 16),
          TextField(
            enabled: !busy,
            controller: label,
            decoration: InputDecoration(
              labelText: widget.reviewTypes == null
                  ? 'Fármaco / revisión'
                  : 'Revisión',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => reviewed = false),
          ),
          const SizedBox(height: 16),
          TextField(
            enabled: !busy,
            controller: instructions,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Indicación del MVZ',
              helperText: widget.reviewTypes == null
                  ? 'Medicación: captura presentación, cantidad, unidad, vía y cuidados indicados.'
                  : 'Describe la revisión indicada; no se registran medicamentos desde este formulario.',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => reviewed = false),
          ),
          const SizedBox(height: 16),
          const Text(
            'Horarios en la zona local de este dispositivo; revisa fecha y hora antes de guardar.',
          ),
          for (final time in times)
            ListTile(
              title: Text(time.toString().substring(0, 16)),
              trailing: IconButton(
                tooltip: 'Quitar horario',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        times.remove(time);
                        reviewed = false;
                      }),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          OutlinedButton.icon(
            onPressed: busy ? null : addTime,
            icon: const Icon(Icons.schedule),
            label: const Text('Añadir horario'),
          ),
          TextField(
            enabled: !busy,
            controller: delay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Aviso de retraso tras (minutos)',
              helperText:
                  'Solo configura el aviso; no modifica la indicación clínica.',
            ),
            onChanged: (_) => setState(() => reviewed = false),
          ),
          CheckboxListTile(
            title: const Text(
              'Revisé paciente, indicación y todos los horarios.',
            ),
            value: reviewed,
            onChanged: busy
                ? null
                : (v) => setState(() => reviewed = v ?? false),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('Guardar indicación'),
          ),
        ],
      ),
    ),
  );
}

class HospitalCageForm extends StatefulWidget {
  const HospitalCageForm({super.key, required this.stay, required this.save});
  final HospitalStay stay;
  final Future<bool> Function(String, String, String) save;
  @override
  State<HospitalCageForm> createState() => _HospitalCageFormState();
}

class _HospitalCageFormState extends State<HospitalCageForm> {
  final exit = FormExitController();
  late final cage = TextEditingController(text: widget.stay.cage);
  final reason = TextEditingController();
  bool busy = false;
  String? error, attempted;
  String operation = newOperationId();
  @override
  void dispose() {
    exit.dispose();
    cage.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final label = hospitalText(cage.text, max: 80, allowEmpty: true);
      final note = hospitalText(reason.text, max: 1000, allowEmpty: true);
      final fingerprint = jsonEncode([label, note]);
      if (attempted != null && attempted != fingerprint) {
        operation = newOperationId();
      }
      attempted = fingerprint;
      final ok = await widget.save(label, note, operation);
      if (!mounted) return;
      if (ok) {
        exit.close(context);
        return;
      }
      setState(
        () => error =
            'No se pudo cambiar la jaula. Actualiza y revisa si está ocupada o cambió la estancia.',
      );
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: cage.text != widget.stay.cage || reason.text.isNotEmpty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Cambiar jaula')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(widget.stay.patientName),
          Text('Ubicación actual: ${widget.stay.cageLabel}'),
          TextField(
            controller: cage,
            enabled: !busy,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nueva jaula / box (opcional)',
              helperText: 'Vacío deja la estancia sin jaula asignada.',
            ),
          ),
          TextField(
            controller: reason,
            enabled: !busy,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
          ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('Guardar ubicación'),
          ),
        ],
      ),
    ),
  );
}

enum HospitalResolutionAction { snooze, notGiven, discharge }

class HospitalResolutionForm extends StatefulWidget {
  const HospitalResolutionForm({
    super.key,
    required this.stay,
    required this.action,
    required this.save,
    this.task,
    this.preview,
  });
  final HospitalStay stay;
  final HospitalResolutionAction action;
  final HospitalTask? task;
  final HospitalDischargePreview? preview;
  final Future<bool> Function(int?, String, String) save;
  @override
  State<HospitalResolutionForm> createState() => _HospitalResolutionFormState();
}

class _HospitalResolutionFormState extends State<HospitalResolutionForm> {
  final exit = FormExitController();
  final reason = TextEditingController();
  String operation = newOperationId();
  String? attempted, error;
  int? minutes;
  bool reviewed = false, busy = false;
  bool get discharge => widget.action == HospitalResolutionAction.discharge;
  bool get snooze => widget.action == HospitalResolutionAction.snooze;
  String get title => discharge
      ? 'Revisar alta hospitalaria'
      : snooze
      ? 'Posponer el aviso'
      : 'No se aplicó';
  @override
  void dispose() {
    exit.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final text = hospitalText(reason.text, max: 500);
      if (!reviewed) {
        throw const FormatException(
          'Revisa el paciente y la acción antes de confirmar.',
        );
      }
      if (snooze && minutes == null) {
        throw const FormatException('Elige cuánto posponer el aviso.');
      }
      if (discharge && widget.preview == null ||
          !discharge && widget.task == null) {
        throw const FormatException('Actualiza la hoja antes de continuar.');
      }
      final fp = jsonEncode([minutes, text]);
      if (attempted != null && attempted != fp) operation = newOperationId();
      attempted = fp;
      final ok = await widget.save(minutes, text, operation);
      if (!mounted) return;
      if (ok) {
        exit.close(context);
        return;
      }
      setState(
        () => error = discharge
            ? 'No se guardó el alta. Actualiza la hoja y revisa otra vez las indicaciones pendientes.'
            : 'No se guardó. Actualiza la hoja: la dosis o tus permisos pueden haber cambiado.',
      );
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: reason.text.isNotEmpty || reviewed || minutes != null,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.stay.patientName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Jaula: ${widget.stay.cageLabel}'),
          if (widget.task != null) ...[
            Text(widget.task!.label),
            Text(widget.task!.instructions),
            Text('Programada: ${widget.task!.dueAt.toLocal()}'),
          ],
          if (discharge) ...[
            Text(
              '${widget.preview?.pending.length ?? 0} indicaciones pendientes se cancelarán por alta.',
            ),
            const Text(
              'Incluye las indicaciones futuras. Las aplicaciones registradas y los saldos se conservan.',
            ),
            for (final t in widget.preview?.pending ?? <Map<String, dynamic>>[])
              ListTile(
                title: Text(t['label'] as String),
                subtitle: Text('${t['instructions']}\n${t['due_at']}'),
              ),
          ] else if (snooze) ...[
            const Text(
              'Solo cambia el aviso; la hora de la indicación se conserva.',
            ),
            DropdownButtonFormField<int>(
              initialValue: minutes,
              decoration: const InputDecoration(labelText: 'Posponer aviso'),
              items: [5, 10, 15, 30]
                  .map(
                    (m) =>
                        DropdownMenuItem(value: m, child: Text('$m minutos')),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      minutes = v;
                      reviewed = false;
                    }),
            ),
          ] else
            const Text(
              'Solo esta dosis quedará como no aplicada. No descuenta producto ni modifica las dosis siguientes.',
            ),
          const SizedBox(height: 16),
          TextField(
            controller: reason,
            enabled: !busy,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => reviewed = false),
          ),
          CheckboxListTile(
            title: Text(
              discharge
                  ? 'Revisé el paciente y todas las indicaciones pendientes.'
                  : 'Revisé el paciente, la dosis y esta acción.',
            ),
            value: reviewed,
            onChanged: busy
                ? null
                : (v) => setState(() => reviewed = v ?? false),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              discharge
                  ? 'Confirmar alta'
                  : snooze
                  ? 'Confirmar posposición'
                  : 'Confirmar que no se aplicó',
            ),
          ),
        ],
      ),
    ),
  );
}
