import '../../patients/domain/patient_contacts.dart';
import '../../patients/presentation/patient_contact_panel.dart';
import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/domain/patient_repository.dart';
import '../application/hospital_alerts.dart';
import '../domain/hospital_models.dart';
import '../domain/hospital_repository.dart';
import 'hospital_view_model.dart';
import 'hospital_forms.dart';

class HospitalScreen extends StatefulWidget {
  const HospitalScreen({
    super.key,
    required this.repository,
    required this.patients,
    required this.member,
    required this.alerts,
    this.onRecordMedication,
    this.initialPatientId,
    this.initialInstructions,
  });
  final String? initialPatientId;
  final String? initialInstructions;
  final HospitalRepository repository;
  final PatientRepository patients;
  final ClinicMembership member;
  final HospitalAlerts alerts;
  final Future<void> Function(HospitalTask)? onRecordMedication;
  @override
  State<HospitalScreen> createState() => _HospitalScreenState();
}

class _HospitalScreenState extends State<HospitalScreen> {
  late final HospitalViewModel model;
  DateTime day = DateTime.now();
  bool table = false;
  Iterable<HospitalStay> get visibleStays => model.snapshot.stays.where(
    (s) =>
        widget.initialPatientId == null ||
        s.patientId == widget.initialPatientId,
  );

  @override
  void initState() {
    super.initState();
    model = HospitalViewModel(widget.repository, widget.member, widget.alerts);
    model.start();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> moveCage(HospitalStay stay) async {
    final repository = widget.repository as HospitalLocationRepository;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HospitalCageForm(
          stay: stay,
          save: (cage, reason, operation) => model.mutate(
            () => repository.moveCage(
              widget.member.clinicId,
              stay,
              cage,
              reason,
              operation,
            ),
            permission: 'hospital.manage',
          ),
        ),
      ),
    );
  }

  Widget cageHistoryTile(Map<String, dynamic> row) {
    final details = row['details'] is Map ? row['details'] as Map : const {};
    String label(Object? value) =>
        value == null || value.toString().trim().isEmpty
        ? 'Sin asignar'
        : value.toString();
    final changed = row['action'] == 'hospital_cage_changed';
    final actor = row['actor_id']?.toString() ?? '';
    final author = actor == widget.member.userId
        ? 'Tú'
        : actor.isEmpty
        ? 'Autor no disponible'
        : 'Integrante · ${actor.substring(0, actor.length < 8 ? actor.length : 8)}';
    final instant = DateTime.tryParse(row['at']?.toString() ?? '')?.toLocal();
    return ListTile(
      title: Text(changed ? 'Cambio de jaula' : 'Ingreso'),
      subtitle: Text(
        '${instant ?? ''} · $author\n${changed
            ? '${label(details['from'])} → ${label(details['to'])}'
            : details.containsKey('cage')
            ? label(details['cage'])
            : 'Ubicación no registrada en este evento'}${details['reason'] == null ? '' : '\n${details['reason']}'}',
      ),
    );
  }

  Future<void> cageHistory(HospitalStay stay) async {
    try {
      final rows = await (widget.repository as HospitalLocationRepository)
          .cageHistory(widget.member.clinicId, stay.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Ubicación · ${stay.patientName}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rows.isEmpty) const Text('Sin cambios registrados.'),
                  for (final row in rows) cageHistoryTile(row),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo consultar el historial de ubicación.'),
          ),
        );
      }
    }
  }

  Future<void> admit() async {
    try {
      final patients = await widget.patients.patients(widget.member.clinicId);
      if (!mounted) return;
      final repository = widget.repository;
      final clinicId = widget.member.clinicId;
      final optionalCage = model.snapshot.optionalCage;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => HospitalAdmitForm(
            patients: patients,
            optionalCage: optionalCage,
            save: (patient, cage, op) async {
              try {
                await repository.admit(clinicId, patient, cage, op);
                return true;
              } catch (_) {
                return false;
              }
            },
          ),
        ),
      );
      if (mounted) await model.refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudieron consultar los pacientes.'),
          ),
        );
      }
    }
  }

  Future<void> prescribe(HospitalStay stay) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HospitalOrderForm(
          stay: stay,
          initialLabel: widget.initialInstructions == null
              ? null
              : 'Revisión de fluidoterapia',
          initialInstructions: widget.initialPatientId == stay.patientId
              ? widget.initialInstructions
              : null,
          reviewTypes: model.snapshot.typedReviews
              ? model.snapshot.reviewTypes
              : null,
          save: (kind, label, instructions, times, delay, op) => model.mutate(
            () => model.snapshot.typedReviews
                ? (widget.repository as HospitalReviewRepository)
                      .scheduleReview(
                        widget.member.clinicId,
                        stay.id,
                        kind,
                        label,
                        instructions,
                        times,
                        delay,
                        op,
                      )
                : widget.repository.prescribe(
                    widget.member.clinicId,
                    stay.id,
                    kind,
                    label,
                    instructions,
                    times,
                    delay,
                    op,
                  ),
            physician: true,
            permission: 'hospital.schedule',
          ),
        ),
      ),
    );
  }

  Future<String?> reason(String title) async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo obligatorio',
                ),
              ),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    context,
                    hospitalText(controller.text, max: 500),
                  );
                } on FormatException {
                  setState(() => error = 'Escribe el motivo.');
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> perform(HospitalStay stay, HospitalTask task) async {
    if (task.prescriptionItemId != null) {
      if (widget.onRecordMedication == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esta tarea requiere registrar cantidad y lote en el registro de medicación.',
            ),
          ),
        );
        return;
      }
      await widget.onRecordMedication!(task);
      if (mounted) await model.refresh();
      return;
    }
    bool checked = false;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            task.kind == 'medicacion'
                ? 'Confirmar administración'
                : 'Confirmar revisión',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${stay.patientName} · Jaula ${stay.cageLabel}\n${task.label}\n${task.instructions}\nHorario original: ${task.dueAt.toLocal()}',
              ),
              CheckboxListTile(
                title: const Text(
                  'Confirmo que ya se realizó para este paciente.',
                ),
                value: checked,
                onChanged: (v) => setState(() => checked = v ?? false),
              ),
              const Text('El servidor registrará tu usuario y la hora actual.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: checked ? () => Navigator.pop(context, true) : null,
              child: const Text('Registrar realizado'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted) await model.perform(task);
  }

  Future<void> medicationFollowup(
    HospitalStay stay,
    HospitalTask task,
    HospitalResolutionAction action,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HospitalResolutionForm(
          stay: stay,
          task: task,
          action: action,
          save: (minutes, why, operation) => model.followup(
            task,
            action == HospitalResolutionAction.snooze ? 'snooze' : 'not_given',
            minutes,
            why,
            operation,
          ),
        ),
      ),
    );
  }

  Future<void> reviewDischarge(HospitalStay stay) async {
    if (!model.snapshot.reviewedDischarge) {
      final why = await reason(
        'Registrar alta y cancelar todas las tareas pendientes',
      );
      if (why != null && mounted) await model.discharge(stay, why);
      return;
    }
    final source = widget.repository;
    if (source is! HospitalResolutionRepository) return;
    try {
      final preview = await (source as HospitalResolutionRepository)
          .dischargePreview(widget.member.clinicId, stay);
      if (!mounted) return;
      if (preview.stayId != stay.id) {
        throw const FormatException('Estancia distinta.');
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => HospitalResolutionForm(
            stay: stay,
            preview: preview,
            action: HospitalResolutionAction.discharge,
            save: (_, why, operation) =>
                model.confirmDischarge(stay, preview, why, operation),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo revisar el alta. Actualiza y comprueba tus permisos.',
            ),
          ),
        );
      }
    }
  }

  Future<void> snooze(HospitalTask task) async {
    int? minutes;
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Posponer el aviso'),
          content: DropdownButton<int>(
            value: minutes,
            hint: const Text('Elige el tiempo'),
            items: [5, 10, 15, 30]
                .map(
                  (m) => DropdownMenuItem(value: m, child: Text('$m minutos')),
                )
                .toList(),
            onChanged: (m) => setState(() => minutes = m ?? minutes),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: minutes == null
                  ? null
                  : () => Navigator.pop(context, minutes),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    if (amount == null || !mounted) return;
    final why = await reason('Motivo de posposición');
    if (why != null && mounted) await model.snooze(task, amount, why);
  }

  Widget taskCard(
    HospitalStay stay,
    HospitalTask task, {
    bool compact = false,
  }) {
    final urgency = task.urgency(model.now());
    final actionable =
        task.state == HospitalTaskState.pending &&
        !model.now().isBefore(task.dueAt);
    final status = switch (urgency) {
      TaskUrgency.done =>
        task.kind == 'medicacion' ? 'Administrado ✓' : 'Revisado ✓',
      TaskUrgency.cancelled =>
        task.resolutionKind == 'not_given'
            ? 'No se aplicó'
            : task.resolutionKind == 'discharge'
            ? 'Cancelada por alta'
            : 'Cancelado',
      TaskUrgency.scheduled => 'Programado',
      TaskUrgency.snoozed => 'Aviso pospuesto',
      TaskUrgency.escalated => 'Retraso · revisión prioritaria',
      TaskUrgency.due => 'Pendiente: horario cumplido',
    };
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${task.dueAt.toLocal().toString().substring(11, 16)} · ${task.label}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(task.instructions),
            Text(
              status,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color:
                    urgency == TaskUrgency.escalated ||
                        urgency == TaskUrgency.due
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            if (task.snoozedUntil?.isAfter(model.now()) ?? false)
              Text(
                'Aviso pospuesto hasta ${task.snoozedUntil!.toLocal().toString().substring(11, 16)} · no registrado como administrado',
              ),
            if (task.resolutionKind != null)
              Text(
                'Registró: ${task.cancelledBy == widget.member.userId ? 'Tú' : task.cancelledBy} · ${task.cancelledAt?.toLocal()}\nMotivo: ${task.cancelReason}',
              ),
            if (task.state == HospitalTaskState.done)
              Text(
                'Usuario que aplicó: ${task.performedBy}\n${task.medicationRecordId == null ? 'Hora del servidor' : 'Hora observada de aplicación'}: ${task.performedAt?.toLocal()}',
              ),
            if (task.state == HospitalTaskState.pending)
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed:
                        model.busy ||
                            !actionable ||
                            !model.canTask(task, 'perform')
                        ? null
                        : () => perform(stay, task),
                    child: Text(
                      task.kind == 'medicacion'
                          ? 'Registrar administración'
                          : 'Registrar revisión',
                    ),
                  ),
                  TextButton(
                    onPressed:
                        model.busy ||
                            !actionable ||
                            !model.canTask(task, 'snooze') ||
                            task.snoozeCount >= 3
                        ? null
                        : () =>
                              task.kind == 'medicacion' &&
                                  model.snapshot.medicationFollowup
                              ? medicationFollowup(
                                  stay,
                                  task,
                                  HospitalResolutionAction.snooze,
                                )
                              : snooze(task),
                    child: const Text('Posponer aviso'),
                  ),
                  if (task.kind == 'medicacion' &&
                      model.snapshot.medicationFollowup &&
                      model.canTask(task, 'not_given') &&
                      widget.repository is HospitalResolutionRepository)
                    TextButton(
                      onPressed: model.busy || !actionable
                          ? null
                          : () => medicationFollowup(
                              stay,
                              task,
                              HospitalResolutionAction.notGiven,
                            ),
                      child: const Text('No se aplicó'),
                    ),
                  if (model.canTask(task, 'cancel'))
                    TextButton(
                      onPressed: model.busy
                          ? null
                          : () async {
                              final why = await reason(
                                'Cancelar esta indicación',
                              );
                              if (why != null && mounted) {
                                await model.cancel(task, why);
                              }
                            },
                      child: const Text('Cancelar'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  bool onDay(HospitalTask task) {
    final local = task.dueAt.toLocal();
    return local.year == day.year &&
        local.month == day.month &&
        local.day == day.day;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final waiting = model.snapshot.tasks
          .where(
            (t) => [
              TaskUrgency.due,
              TaskUrgency.escalated,
            ].contains(t.urgency(model.now())),
          )
          .length;
      final tasks = model.snapshot.tasks.where(onDay).toList();
      final hours = tasks.map((t) => t.dueAt.toLocal().hour).toSet().toList()
        ..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hospitalización',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (widget.initialInstructions != null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Selecciona programar una revisión en la ficha de este paciente. Revisa el borrador, elige el procedimiento y los horarios antes de guardar. Si no está hospitalizado, registra primero su ingreso.',
              ),
            ),
          if (waiting > 0)
            Semantics(
              liveRegion: true,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '$waiting tareas pendientes con horario cumplido. Revisa la hoja antes de administrar.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          Text(widget.alerts.status),
          Text(widget.alerts.backend.timingNotice),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.alerts.backend.supported)
                OutlinedButton(
                  onPressed: () async {
                    await widget.alerts.enable();
                    await model.refresh();
                  },
                  child: const Text('Activar / revisar permisos de avisos'),
                ),
              if (widget.alerts.enabled)
                TextButton(
                  onPressed: widget.alerts.disable,
                  child: const Text('Desactivar avisos'),
                ),
              if (model.canManageAdmission)
                FilledButton.icon(
                  onPressed: model.busy ? null : admit,
                  icon: const Icon(Icons.add),
                  label: const Text('Ingresar paciente'),
                ),
              OutlinedButton(
                onPressed: model.busy ? null : () => model.refresh(),
                child: const Text('Actualizar hoja'),
              ),
            ],
          ),
          if (model.busy) const LinearProgressIndicator(),
          if (model.error != null)
            Text(
              model.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (model.alarmError != null)
            Text(
              model.alarmError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (date != null && mounted) setState(() => day = date);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text('Fecha: ${day.toIso8601String().substring(0, 10)}'),
              ),
              ChoiceChip(
                label: const Text('Fichas por jaula'),
                selected: !table,
                onSelected: (_) => setState(() => table = false),
              ),
              ChoiceChip(
                label: const Text('Paciente × hora'),
                selected: table,
                onSelected: (_) => setState(() => table = true),
              ),
            ],
          ),
          if (visibleStays.isEmpty && !model.busy && model.error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay estancias activas disponibles para esta selección.',
              ),
            ),
          if (table && hours.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(300),
                border: TableBorder.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                children: [
                  TableRow(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Paciente / jaula'),
                      ),
                      for (final h in hours)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('${h.toString().padLeft(2, '0')}:00'),
                        ),
                    ],
                  ),
                  for (final stay in visibleStays)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '${stay.patientName}\nJaula ${stay.cageLabel}',
                          ),
                        ),
                        for (final h in hours)
                          Column(
                            children: [
                              for (final task in tasks.where(
                                (t) =>
                                    t.stayId == stay.id &&
                                    t.dueAt.toLocal().hour == h,
                              ))
                                taskCard(stay, task, compact: true),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            )
          else
            for (final stay in visibleStays)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Jaula ${stay.cageLabel} · ${stay.patientName}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(stay.species),
                      if (widget.patients is PatientContactRepository &&
                          [
                            ClinicRole.admin,
                            ClinicRole.mvz,
                            ClinicRole.recepcion,
                          ].contains(widget.member.role))
                        ExpansionTile(
                          title: const Text('Contacto del tutor'),
                          children: [
                            PatientContactPanel(
                              key: ValueKey(
                                'hospital-contact:${widget.member.userId}:${widget.member.clinicId}:${stay.patientId}',
                              ),
                              repository:
                                  widget.patients as PatientContactRepository,
                              clinic: widget.member.clinicId,
                              patient: stay.patientId,
                              patientName: stay.patientName,
                              onSaved: () => model.refresh(),
                            ),
                          ],
                        ),
                      if (model.snapshot.cageChanges &&
                          widget.repository is HospitalLocationRepository)
                        Wrap(
                          children: [
                            if (model.canMoveCage)
                              TextButton(
                                onPressed: model.busy
                                    ? null
                                    : () => moveCage(stay),
                                child: const Text('Cambiar jaula'),
                              ),
                            TextButton(
                              onPressed: model.busy
                                  ? null
                                  : () => cageHistory(stay),
                              child: const Text('Historial de ubicación'),
                            ),
                          ],
                        ),
                      if (model.canSchedule || model.canDischarge)
                        Wrap(
                          spacing: 8,
                          children: [
                            if (model.canSchedule &&
                                (!model.snapshot.typedReviews ||
                                    widget.repository
                                        is HospitalReviewRepository))
                              TextButton(
                                onPressed: model.busy
                                    ? null
                                    : () => prescribe(stay),
                                child: Text(
                                  model.snapshot.typedReviews
                                      ? 'Programar revisión'
                                      : 'Añadir tratamiento / revisión',
                                ),
                              ),
                            if (model.canDischarge)
                              TextButton(
                                onPressed: model.busy
                                    ? null
                                    : () => reviewDischarge(stay),
                                child: const Text('Registrar alta'),
                              ),
                          ],
                        ),
                      if (!tasks.any((t) => t.stayId == stay.id))
                        const Text('Sin tratamientos en la fecha elegida.'),
                      for (final task in tasks.where(
                        (t) => t.stayId == stay.id,
                      ))
                        taskCard(stay, task),
                    ],
                  ),
                ),
              ),
        ],
      );
    },
  );
}
