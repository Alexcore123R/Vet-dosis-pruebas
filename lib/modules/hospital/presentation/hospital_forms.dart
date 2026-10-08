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
  });
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
      final label = hospitalText(cage.text, max: 80);
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
            decoration: const InputDecoration(
              labelText: 'Jaula / box',
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
            onPressed: busy ? null : save,
            child: const Text('Registrar ingreso'),
          ),
        ],
      ),
    ),
  );
}

class HospitalOrderForm extends StatefulWidget {
  const HospitalOrderForm({super.key, required this.stay, required this.save});
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
      kind != 'medicacion';
  @override
  void initState() {
    super.initState();
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
      appBar: AppBar(title: const Text('Indicar tratamiento / revisión')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('${widget.stay.patientName} · Jaula ${widget.stay.cage}'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: const [
              DropdownMenuItem(value: 'medicacion', child: Text('Medicación')),
              DropdownMenuItem(value: 'revision', child: Text('Revisión')),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    kind = v ?? kind;
                    reviewed = false;
                  }),
          ),
          const SizedBox(height: 16),
          TextField(
            enabled: !busy,
            controller: label,
            decoration: const InputDecoration(
              labelText: 'Fármaco / revisión',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => reviewed = false),
          ),
          const SizedBox(height: 16),
          TextField(
            enabled: !busy,
            controller: instructions,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Indicación del MVZ',
              helperText:
                  'Medicación: captura presentación, cantidad, unidad, vía y cuidados indicados.',
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
