import '../domain/service_catalog.dart';
import 'appointment_links_panel.dart';
import 'appointment_care_panel.dart';
import '../domain/appointment_care.dart';
import 'appointment_summary.dart';
import '../../../vet_ui/vet_components.dart';
import '../../auth/domain/staff_labels.dart';
import 'appointment_patient_picker.dart';
import '../../backup/domain/backup_archive.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../inventory/domain/inventory_models.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/operations_repository.dart';
import 'operations_view_model.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({
    super.key,
    required this.repository,
    required this.member,
    this.onOpenPatient,
    this.onNavigate,
    this.canOpenInventory = false,
    this.canOpenSales = false,
    this.initialSection = 'appointments',
    this.initialPatientId,
  });
  final Future<void> Function(String)? onOpenPatient;
  final String? initialPatientId;
  final ValueChanged<String>? onNavigate;
  final bool canOpenInventory, canOpenSales;
  final OperationsRepository repository;
  final String initialSection;
  final ClinicMembership member;
  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen>
    with WidgetsBindingObserver {
  late final model = OperationsViewModel(
    widget.repository,
    widget.member.clinicId,
  );
  String section = 'appointments', filter = 'pendientes';
  DateTime? calendarDay;
  bool careDay = true;
  bool get careEnabled => widget.repository is AppointmentCareRepository;
  String? appointmentState;
  List<Map<String, dynamic>> get visibleAppointments => model
      .rows('appointments')
      .where(
        (a) =>
            (!careEnabled ||
                !careDay ||
                (model.careWindow != null &&
                    inCareQueue(
                      a,
                      DateTime.parse(model.careWindow!['day_start'] as String),
                      DateTime.parse(model.careWindow!['day_end'] as String),
                    ))) &&
            (widget.initialPatientId == null ||
                a['patient_id'] == widget.initialPatientId) &&
            (appointmentState == null || a['state'] == appointmentState) &&
            (calendarDay == null ||
                DateUtils.isSameDay(
                  DateTime.parse(a['starts_at'] as String).toLocal(),
                  calendarDay,
                )),
      )
      .toList();
  bool get admin => widget.member.role == ClinicRole.admin;
  bool canWrite(String permission, {required bool legacy}) =>
      model.explicitPermissions ? model.allowed(permission) : legacy;
  String sectionTitle(String value) => switch (value) {
    'appointments' => 'Agenda y citas',
    'services' => 'Servicios',
    'tasks' => 'Pendientes del equipo',
    'messages' => 'Mensajes del equipo',
    'suppliers' => 'Proveedores',
    'acts' => 'Servicios realizados',
    _ => 'Operación de clínica',
  };
  String sectionPermission(String value) {
    if (model.sectionReason(value) == 'clinic_plan_required') {
      return 'el plan de la clínica para las herramientas de equipo';
    }
    return switch (value) {
      'appointments' => 'appointment.read o appointment.manage',
      'services' => 'service.read o service.manage',
      'tasks' || 'messages' => 'team.read o team.manage',
      'suppliers' => 'supplier.read o supplier.manage',
      'acts' => 'service.act.read o service.act.record',
      _ => 'permiso de operación',
    };
  }

  Map<String, String> get people => {
    for (final p in model.rows('members'))
      p['user_id'] as String: staffLabel(
        p['user_id'] as String,
        model.rows('people'),
        role: p['role'] as String,
      ),
  };
  String get activeSection =>
      model.explicitPermissions && !model.sectionAllowed(section)
      ? 'blocked'
      : section;
  String person(String id) => staffLabel(id, model.rows('people'));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    section = widget.initialSection;
    model.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      model.load();
    } else {
      model.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    super.dispose();
  }

  Future<void> form(
    String title,
    String action,
    List<RxField> fields, {
    Map<String, dynamic> initial = const {},
  }) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: title,
          fields: fields,
          initial: initial,
          submit: (d, op) async {
            if (action == 'appointment' || action == 'appointment_reschedule') {
              validateAppointmentTimes(d);
            }
            try {
              final payload = Map<String, dynamic>.from(d);
              if (action == 'appointment' && payload['kind'] == 'cirugia') {
                final surgeryType = '${payload.remove('surgery_type') ?? ''}'
                    .trim();
                if (surgeryType.isNotEmpty) {
                  final notes = '${payload['notes'] ?? ''}'.trim();
                  payload['notes'] = [
                    if (notes.isNotEmpty) notes,
                    'Tipo de cirugía: $surgeryType',
                  ].join('\n');
                }
              }
              await widget.repository.write(
                widget.member.clinicId,
                action,
                payload,
                op,
              );
            } catch (e) {
              throw FormatException(operationError(e));
            }
          },
        ),
      ),
    );
    if (ok == true && mounted) await model.load();
  }

  Future<void> openPatient(String id) async {
    await widget.onOpenPatient?.call(id);
    if (mounted) await model.load();
  }

  Future<void> confirmAppointmentState(
    Map<String, dynamic> appointment,
    String state,
  ) async {
    final label = switch (state) {
      'en_atencion' => 'iniciar la atención',
      'listo' => 'marcar el servicio como listo',
      'entregado' => 'marcar la entrega',
      'cancelado' => 'cancelar la cita',
      _ => 'actualizar la cita',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar actualización'),
        content: Text('¿Quieres $label de ${appointment['patient_name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await form(
      'Actualizar cita',
      'appointment_state',
      state == 'cancelado'
          ? const [RxField('reason', 'Motivo de cancelación', required: true)]
          : const [],
      initial: {
        'id': appointment['id'],
        'version': appointment['version'],
        'state': state,
      },
    );
  }

  Future<void> newAppointment() async {
    Map<String, dynamic> patient = {};
    if ((model.explicitPermissions
            ? model.allowed('patient.read')
            : widget.member.role != ClinicRole.estilista) &&
        widget.repository is AppointmentPatientRepository) {
      final selected = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => AppointmentPatientPicker(
            repository: widget.repository as AppointmentPatientRepository,
            clinic: widget.member.clinicId,
          ),
        ),
      );
      if (selected == null || !mounted) return;
      patient = selected;
    }
    await form(
      patient.isEmpty
          ? 'Nueva cita sin expediente'
          : 'Cita para ${patient['name']}',
      'appointment',
      [
        if (patient.isEmpty)
          const RxField('patient_name', 'Paciente', required: true),
        if (patient.isEmpty)
          const RxField('species', 'Especie', required: true),
        const RxField(
          'kind',
          'Tipo',
          type: 'select',
          options: {
            'consulta': 'Consulta',
            'seguimiento': 'Seguimiento',
            'estetica': 'Estética / baño / peluquería',
            'cirugia': 'Cirugía',
            'analisis': 'Análisis / toma de muestras',
            'hospital_visita': 'Visita de hospitalizado',
            'vacunacion': 'Vacunación / desparasitación',
            'entrega': 'Entrega / alta',
            'otro': 'Otro servicio',
          },
          required: true,
        ),
        const RxField('surgery_type', 'Tipo de cirugía (si aplica)'),
        RxField(
          'professional_id',
          model.explicitPermissions ? 'Integrante asignado' : 'Profesional',
          type: 'select',
          options: people,
          required: true,
        ),
        const RxField(
          'starts_at',
          'Inicio',
          type: 'local_instant',
          required: true,
        ),
        const RxField('ends_at', 'Fin', type: 'local_instant', required: true),
        const RxField('notes', 'Observaciones'),
      ],
      initial: patient.isEmpty
          ? {}
          : {
              'patient_id': patient['id'],
              'patient_name': patient['name'],
              'species': patient['species'],
            },
    );
  }

  Future<void> medical() async {
    try {
      var profiles = await widget.repository.medical(widget.member.clinicId);
      if (!mounted) return;
      final own = profiles
          .where((p) => p['user_id'] == widget.member.userId)
          .firstOrNull;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RxEntryScreen(
            title: 'Mi ficha médica · acceso restringido',
            initial: Map<String, dynamic>.from(own?['details'] as Map? ?? {}),
            fields: const [
              RxField('blood', 'Grupo sanguíneo'),
              RxField('allergies', 'Alergias'),
              RxField('conditions', 'Antecedentes'),
              RxField('vaccines', 'Vacunación'),
              RxField('emergency', 'Contacto de emergencia'),
              RxField(
                'consent',
                'Consiento el registro; solo yo y el admin de esta clínica podrán consultarlo',
                type: 'checkbox',
                required: true,
              ),
              RxField(
                'erase',
                'Retirar la ficha y su consentimiento',
                type: 'checkbox',
              ),
            ],
            submit: (d, op) async {
              if (d['consent'] != true) {
                throw const FormatException('Confirma tu consentimiento.');
              }
              final erase = d.remove('erase') == true;
              d.remove('consent');
              await widget.repository.medical(
                widget.member.clinicId,
                details: erase ? {} : d,
                consent: true,
              );
            },
          ),
        ),
      );
      if (admin && mounted) {
        profiles = await widget.repository.medical(widget.member.clinicId);
      }
      if (admin && mounted && profiles.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Fichas consentidas del personal'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  for (final p in profiles)
                    ListTile(
                      title: Text(person(p['user_id'] as String)),
                      subtitle: Text('${p['details']}'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          activeSection == 'blocked'
              ? sectionTitle(section)
              : sectionTitle(activeSection),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'La agenda y los servicios no autorizan procedimientos ni sustituyen el registro clínico.',
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final e in {
              'appointments': 'Agenda y citas',
              'services': 'Servicios',
              if (!widget.member.isPersonal) 'tasks': 'Pendientes',
              if (!widget.member.isPersonal) 'messages': 'Mensajes',
              'suppliers': 'Distribuidores',
              'acts': 'Desempeño',
            }.entries)
              if (!model.explicitPermissions || model.sectionAllowed(e.key))
                ChoiceChip(
                  label: Text(e.value),
                  selected: section == e.key,
                  onSelected: (_) => setState(() => section = e.key),
                ),
            TextButton(
              onPressed: model.busy
                  ? null
                  : () => form(
                      'Mi nombre visible en la clínica',
                      'display_name',
                      const [
                        RxField(
                          'name',
                          'Nombre que verán los integrantes de esta clínica',
                          required: true,
                        ),
                      ],
                      initial: {
                        'name':
                            model
                                .rows('people')
                                .where(
                                  (p) => p['user_id'] == widget.member.userId,
                                )
                                .firstOrNull?['display_name'] ??
                            '',
                      },
                    ),
              child: const Text('Mi nombre en el equipo'),
            ),
            if (!model.explicitPermissions)
              TextButton(
                onPressed: model.busy ? null : medical,
                child: const Text('Ficha médica privada'),
              ),
            IconButton(
              tooltip: 'Actualizar registros',
              onPressed: model.busy ? null : model.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (model.busy) const LinearProgressIndicator(),
        if (model.error != null)
          Text(
            model.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (activeSection == 'blocked')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Esta sección no está habilitada para tu cuenta.'),
                  const SizedBox(height: 8),
                  Text(
                    'El acceso requiere ${sectionPermission(section)}. Pide a una persona administradora de la clínica que revise “Permisos y habilitación”.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: model.busy ? null : model.load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar permisos'),
                  ),
                ],
              ),
            ),
          ),
        if (activeSection == 'appointments') ...[
          if (model.linksError != null) Text(model.linksError!),
          if (widget.initialPatientId != null)
            const Text('Atenciones del paciente seleccionado en Pacientes.'),
          if (!model.busy && model.error == null)
            AppointmentSummary(
              rows: model.rows('appointments'),
              selectedState: appointmentState,
              onStateChanged: (value) =>
                  setState(() => appointmentState = value),
            ),
          if (careEnabled) ...[
            FilterChip(
              label: const Text('Atención del día y pendientes anteriores'),
              selected: careDay,
              onSelected: (value) => setState(() => careDay = value),
            ),
            if (model.careWindow != null && careDay)
              Text(
                '${model.careWindow!['day']} · ${model.careWindow!['timezone']} · ${visibleAppointments.length} citas',
              ),
            if (model.careError != null) Text(model.careError!),
          ],
          VetActionButton(
            label: 'Agendar cita',
            icon: Icons.add,
            onPressed:
                model.busy ||
                    (model.explicitPermissions &&
                        !model.allowed('appointment.manage'))
                ? null
                : newAppointment,
          ),
          const SizedBox(height: 14),
          VetCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              title: const Text('Calendario'),
              children: [
                CalendarDatePicker(
                  initialDate: calendarDay ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 90)),
                  lastDate: DateTime(DateTime.now().year + 5, 12, 31),
                  onDateChanged: (d) => setState(() => calendarDay = d),
                ),
                TextButton(
                  onPressed: () => setState(() => calendarDay = null),
                  child: const Text('Mostrar todas las citas'),
                ),
              ],
            ),
          ),
          if (!model.busy && model.error == null && visibleAppointments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                appointmentState != null
                    ? 'No hay citas con ese estado para la selección actual.'
                    : calendarDay == null
                    ? 'No hay citas registradas.'
                    : 'No hay citas para el día seleccionado.',
              ),
            ),
          for (final a in visibleAppointments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: VetCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  onTap:
                      a['patient_id'] != null &&
                          widget.onOpenPatient != null &&
                          (!model.explicitPermissions ||
                              model.allowed('patient.read'))
                      ? () => openPatient(a['patient_id'] as String)
                      : null,
                  title: Text(
                    '${a['patient_name']} · ${appointmentKindLabel(a['kind'])}${a['patient_id'] == null ? '' : ' · Vinculado al expediente'}',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppointmentDetails(
                        appointment: a,
                        stateLabel: appointmentStateLabel(a['state'] as String),
                      ),
                      Text(
                        'Responsable: ${a['professional_id'] is String ? person(a['professional_id'] as String) : 'Sin asignar'}',
                      ),
                      if (a['patient_id'] != null &&
                          widget.onOpenPatient != null &&
                          (!model.explicitPermissions ||
                              model.allowed('patient.read')))
                        TextButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text(
                            'Abrir expediente / registrar evolución',
                          ),
                          onPressed: () =>
                              openPatient(a['patient_id'] as String),
                        ),
                      if (careEnabled)
                        AppointmentCarePanel(
                          key: ValueKey(
                            'care-${widget.member.userId}-${widget.member.clinicId}-${a['id']}-${a['version']}',
                          ),
                          appointment: a,
                          data: model.care[a['id']],
                          repository:
                              widget.repository as AppointmentCareRepository,
                          clinic: widget.member.clinicId,
                          onSaved: model.load,
                          isCurrent: () =>
                              mounted &&
                              model.care[a['id']] != null &&
                              model
                                  .rows('appointments')
                                  .any(
                                    (r) =>
                                        r['id'] == a['id'] &&
                                        r['version'] == a['version'],
                                  ),
                        ),
                      AppointmentLinksPanel(
                        data: model.links[a['id']],
                        patientName:
                            a['patient_name'] as String? ?? 'el paciente',
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled:
                        !model.explicitPermissions ||
                        model.allowed('appointment.manage'),
                    onSelected: (state) => state == 'reprogramar'
                        ? form(
                            'Reprogramar cita',
                            'appointment_reschedule',
                            const [
                              RxField(
                                'starts_at',
                                'Nuevo inicio',
                                type: 'local_instant',
                                required: true,
                              ),
                              RxField(
                                'ends_at',
                                'Nuevo fin',
                                type: 'local_instant',
                                required: true,
                              ),
                              RxField(
                                'reason',
                                'Motivo del cambio',
                                required: true,
                              ),
                            ],
                            initial: {
                              'id': a['id'],
                              'version': a['version'],
                              'starts_at': a['starts_at'],
                              'ends_at': a['ends_at'],
                            },
                          )
                        : confirmAppointmentState(a, state),
                    itemBuilder: (_) => [
                      if (a['state'] == 'agendado')
                        const PopupMenuItem(
                          value: 'reprogramar',
                          child: Text('Reprogramar'),
                        ),
                      for (final s in switch (a['state']) {
                        'agendado' =>
                          careEnabled
                              ? ['cancelado']
                              : ['en_atencion', 'cancelado'],
                        'en_atencion' =>
                          careEnabled ? ['cancelado'] : ['listo', 'cancelado'],
                        'listo' => careEnabled ? <String>[] : ['entregado'],
                        _ => <String>[],
                      })
                        PopupMenuItem(
                          value: s,
                          child: Text(appointmentStateLabel(s)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (activeSection == 'services' &&
            !model.busy &&
            model.data.isNotEmpty) ...[
          if (canWrite('service.manage', legacy: admin))
            FilledButton(
              onPressed: () => service(),
              child: const Text('Nuevo servicio'),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Organiza los servicios que ofrece tu clínica. Elige una categoría y agrega un servicio con su nombre y precio. Las cirugías pueden llevar el nombre del procedimiento.',
            ),
          ),
          for (final category in serviceCategories.entries)
            ExpansionTile(
              key: ValueKey('service-category-${category.key}'),
              title: Text(category.value),
              subtitle: Text(
                '${model.rows('services').where((s) => serviceCategory(s) == category.key).length} servicios registrados',
              ),
              children: [
                if (canWrite('service.manage', legacy: admin))
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final example in serviceExamples[category.key]!)
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: Text(example),
                          onPressed: () => service(null, category.key, example),
                        ),
                    ],
                  ),
                if (canWrite('service.manage', legacy: admin))
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'Otro servicio / subcategoría personalizada',
                    ),
                    onPressed: () => service(null, category.key),
                  ),
                for (final sub in <String>{
                  ...?serviceSubcategories[category.key],
                  for (final row
                      in model
                          .rows('services')
                          .where((s) => serviceCategory(s) == category.key))
                    serviceSubcategory(row),
                })
                  ExpansionTile(
                    title: Text(sub.isEmpty ? 'Sin subcategoría' : sub),
                    children: [
                      if (canWrite('service.manage', legacy: admin))
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar servicio aquí'),
                          onPressed: () => service(null, category.key, '', sub),
                        ),
                      for (final row
                          in model
                              .rows('services')
                              .where(
                                (s) =>
                                    serviceCategory(s) == category.key &&
                                    serviceSubcategory(s) == sub,
                              ))
                        ListTile(
                          title: Text('${row['name']} · \$${row['price']}'),
                          subtitle: Text(
                            'Comisión: ${row['commission_kind']} ${row['commission_value']}',
                          ),
                          trailing: canWrite('service.manage', legacy: admin)
                              ? IconButton(
                                  tooltip: 'Editar servicio',
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => service(row),
                                )
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
        ],
        if (activeSection == 'services' &&
            !model.busy &&
            model.sectionAllowed('services'))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Venta de productos y farmacia',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Alimentos, accesorios, higiene y medicamentos. Gestiona existencias y precios en Inventario y registra las ventas en Caja.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            widget.canOpenInventory && widget.onNavigate != null
                            ? () => widget.onNavigate!('Inventario')
                            : null,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Productos y farmacia'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            widget.canOpenSales && widget.onNavigate != null
                            ? () => widget.onNavigate!('Caja')
                            : null,
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Registrar venta'),
                      ),
                    ],
                  ),
                  if (!widget.canOpenInventory || !widget.canOpenSales)
                    const Text(
                      'Los accesos se habilitan según tus permisos de Inventario y Caja.',
                    ),
                ],
              ),
            ),
          ),
        if (activeSection == 'tasks') ...[
          if (canWrite('team.manage', legacy: !widget.member.isPersonal))
            FilledButton(
              onPressed: () => form('Nuevo pendiente', 'task', [
                const RxField('title', 'Pendiente', required: true),
                RxField(
                  'assigned_to',
                  'Asignado a (vacío: todos)',
                  type: 'select',
                  options: people,
                ),
                const RxField(
                  'priority',
                  'Prioridad',
                  type: 'select',
                  options: {
                    'urgente': 'Urgente',
                    'media': 'Media',
                    'baja': 'Baja',
                  },
                  required: true,
                ),
              ]),
              child: const Text('Crear pendiente'),
            ),
          DropdownButton<String>(
            value: filter,
            items: [
              for (final f in ['pendientes', 'completadas', 'todas'])
                DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) => setState(() => filter = v!),
          ),
          for (final t
              in model
                  .rows('tasks')
                  .where(
                    (t) =>
                        filter == 'todas' ||
                        (filter == 'pendientes') == (t['completed_at'] == null),
                  ))
            ListTile(
              title: Text('${t['title']} · ${t['priority']}'),
              subtitle: Text(
                t['assigned_to'] == null
                    ? 'Todos'
                    : person(t['assigned_to'] as String),
              ),
              trailing:
                  t['completed_at'] == null &&
                      canWrite('team.manage', legacy: !widget.member.isPersonal)
                  ? IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () => form(
                        'Completar pendiente',
                        'task_complete',
                        const [],
                        initial: {'id': t['id']},
                      ),
                    )
                  : const Icon(Icons.done_all),
            ),
        ],
        if (activeSection == 'messages') ...[
          if (canWrite('team.manage', legacy: !widget.member.isPersonal))
            FilledButton(
              onPressed: () => form('Mensaje al equipo', 'message', const [
                RxField(
                  'category',
                  'Categoría',
                  type: 'select',
                  options: {
                    'general': 'General',
                    'urgente': 'Urgente',
                    'aviso': 'Aviso',
                    'turno': 'Turno',
                  },
                  required: true,
                ),
                RxField(
                  'body',
                  'Mensaje (sin datos sensibles de pacientes o personal)',
                  required: true,
                ),
              ]),
              child: const Text('Escribir mensaje'),
            ),
          for (final m in model.rows('messages'))
            ListTile(
              title: Text('${m['category']} · ${m['body']}'),
              subtitle: Text(
                '${person(m['author_id'] as String)} · ${m['created_at']}',
              ),
            ),
        ],
        if (activeSection == 'suppliers') ...[
          if (canWrite(
            'supplier.manage',
            legacy: admin || widget.member.role == ClinicRole.recepcion,
          ))
            FilledButton(
              onPressed: () => form('Distribuidor', 'supplier', const [
                RxField('name', 'Nombre', required: true),
                RxField('phone', 'Teléfono con código de país'),
                RxField('notes', 'Notas'),
              ]),
              child: const Text('Agregar distribuidor'),
            ),
          for (final s in model.rows('suppliers'))
            ListTile(
              title: Text('${s['name']}'),
              subtitle: Text(
                [
                  if ('${s['phone'] ?? ''}'.trim().isNotEmpty)
                    '${s['phone']}'.trim(),
                  if ('${s['notes'] ?? ''}'.trim().isNotEmpty)
                    '${s['notes']}'.trim(),
                ].join(' · '),
              ),
              trailing: PopupMenuButton<String>(
                itemBuilder: (_) => [
                  for (final x in ['WhatsApp', 'Llamar', 'SMS'])
                    PopupMenuItem(value: x, child: Text(x)),
                ],
                onSelected: (x) async {
                  final p = (s['phone'] as String).replaceAll(
                    RegExp(r'[^0-9+]'),
                    '',
                  );
                  if (p.isEmpty) return;
                  final uri = x == 'WhatsApp'
                      ? Uri.https('wa.me', p.replaceAll('+', ''))
                      : Uri(scheme: x == 'Llamar' ? 'tel' : 'sms', path: p);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ),
        ],
        if (activeSection == 'acts') ...[
          if (canWrite(
            'service.act.record',
            legacy: admin || widget.member.role == ClinicRole.recepcion,
          ))
            FilledButton(
              onPressed: () => form(
                'Registrar servicio realizado',
                'service_act',
                [
                  RxField(
                    'service_id',
                    'Servicio',
                    type: 'select',
                    options: {
                      for (final s in model.rows('services'))
                        s['id'] as String: s['name'] as String,
                    },
                    required: true,
                  ),
                  RxField(
                    'professional_id',
                    'Quién realizó el servicio',
                    type: 'select',
                    options: admin || widget.member.role == ClinicRole.recepcion
                        ? people
                        : {widget.member.userId: widget.member.role.label},
                    required: true,
                  ),
                  RxField(
                    'appointment_id',
                    'Cita opcional',
                    type: 'select',
                    options: {
                      for (final a in model.rows('appointments'))
                        a['id'] as String: a['patient_name'] as String,
                    },
                  ),
                ],
              ),
              child: const Text('Registrar servicio realizado'),
            ),
          if (model.allowed('service.act.read') || !model.explicitPermissions)
            TextButton(
              onPressed: exportPerformance,
              child: const Text('Exportar servicios y comisiones CSV'),
            ),
          for (final e in performance.entries)
            ListTile(
              title: Text(person(e.key)),
              subtitle: Text(
                'Comisión registrada: ${e.value[0].display} · cobrada: ${e.value[1].display}',
              ),
            ),
          const Text(
            'Servicios realizados y comisión congelada. “Cobrado” exige venta vigente en caja; las devoluciones se muestran por separado en inventario.',
          ),
          for (final a in model.rows('acts'))
            ListTile(
              title: Text('${a['name']} · \$${a['price']}'),
              subtitle: Text(
                '${a['professional_id'] is String ? person(a['professional_id'] as String) : 'Sin asignar'} · comisión \$${a['commission']} · ${a['paid'] == true ? 'Cobrado' : 'Pendiente de cobro'}',
              ),
            ),
          if (!model.allowed('service.act.read') && model.explicitPermissions)
            const Text(
              'Solo se muestran los servicios realizados por tu cuenta.',
            ),
        ],
        if (!model.busy &&
            model.error == null &&
            activeSection != 'appointments' &&
            activeSection != 'blocked' &&
            model.rows(section).isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin registros visibles en esta sección.'),
          ),
      ],
    ),
  );

  Map<String, List<Money>> get performance {
    final sums = <String, List<Money>>{};
    for (final a in model.rows('acts')) {
      final key = a['professional_id'] as String;
      final v = sums.putIfAbsent(
        key,
        () => [Money(BigInt.zero), Money(BigInt.zero)],
      );
      final commission = Money.parse(a['commission'] as String);
      v[0] = v[0] + commission;
      if (a['paid'] == true) v[1] = v[1] + commission;
    }
    return sums;
  }

  Future<void> exportPerformance() async {
    try {
      final csv = BackupArchive.tableCsv([
        for (final act in model.rows('acts'))
          {
            ...act,
            'professional_name': person(act['professional_id'] as String),
          },
      ]);
      await FilePicker.saveFile(
        fileName: 'servicios-comisiones.csv',
        bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    }
  }

  Future<void> service([
    Map<String, dynamic>? s,
    String category = 'otro',
    String name = '',
    String subcategory = '',
  ]) => form(
    s == null ? 'Nuevo servicio' : 'Editar servicio',
    'service',
    const [
      RxField(
        'category',
        'Categoría del servicio',
        type: 'select',
        options: serviceCategories,
        required: true,
      ),
      RxField('name', 'Nombre del servicio / tipo de cirugía', required: true),
      RxField('subcategory', 'Subcategoría (puedes escribir una nueva)'),
      RxField('price', 'Precio MXN', required: true),
      RxField(
        'commission_kind',
        'Tipo de comisión',
        type: 'select',
        options: {'porcentaje': 'Porcentaje', 'bono': 'Bono fijo MXN'},
        required: true,
      ),
      RxField('commission_value', 'Valor de comisión', required: true),
    ],
    initial: s == null
        ? {
            'category': category,
            'subcategory': subcategory,
            'name': name,
            'commission_kind': 'bono',
            'commission_value': '0',
          }
        : {...s, 'category': serviceCategory(s)},
  );
}

String appointmentStateLabel(String state) => switch (state) {
  'agendado' => 'Agendada',
  'en_atencion' => 'En atención',
  'listo' => 'Lista para entrega',
  'entregado' => 'Entregada',
  'cancelado' => 'Cancelada',
  _ => state,
};
