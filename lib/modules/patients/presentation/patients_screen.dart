import '../domain/patient_contacts.dart';
import '../../ai/domain/ai_repository.dart';
import '../domain/patient_timeline.dart';
import 'patient_contact_panel.dart';
import 'contact_actions.dart';
import 'dart:async';
import '../domain/patient_activity.dart';
import '../application/patient_activity_model.dart';
import '../domain/clinical_record_fields.dart';
import 'preventive_booklet.dart';
import 'preventive_screen.dart';
import '../domain/preventive_repository.dart';
import '../../../core/widgets/workspace_panel.dart';
import 'patient_catalog.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../core/domain/plan_errors.dart';
import '../domain/patient_models.dart';
import '../domain/patient_repository.dart';
import 'patient_view_model.dart';
import 'patient_form.dart';
import 'event_form.dart';
import 'signature_pad.dart';
import 'weight_chart.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({
    super.key,
    required this.repository,
    required this.member,
    this.onOpenClinical,
    this.initialPatientId,
    this.onOpenActivity,
    this.canOpenActivity,
    this.ai,
  });
  final String? initialPatientId;
  final AiRepository? ai;
  final bool Function(String)? canOpenActivity;
  final Future<void> Function(String destination, String patientId)?
  onOpenActivity;
  final PatientRepository repository;
  final ClinicMembership member;
  final Future<void> Function(VetPatient)? onOpenClinical;
  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen>
    with WidgetsBindingObserver {
  late final PatientViewModel model;
  final search = TextEditingController();
  final historySearch = TextEditingController();
  String query = '';
  String? species;
  String historyQuery = '';
  EventKind? historyKind;
  bool historyOldestFirst = false, historyByReason = false;
  PatientActivityModel? activity;
  PatientActivityKind? activityFilter;
  Timer? activityTimer;
  bool foreground = true;

  @override
  void initState() {
    super.initState();
    model = PatientViewModel(widget.repository, widget.member);
    WidgetsBinding.instance.addObserver(this);
    if (widget.repository is PatientActivityRepository) {
      activity = PatientActivityModel(
        widget.repository as PatientActivityRepository,
        widget.member.clinicId,
      );
      activity!.load();
      activityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (foreground) activity?.load();
      });
    }
    openInitialPatient();
  }

  Future<void> openInitialPatient() async {
    await model.load();
    if (!mounted || widget.initialPatientId == null || model.error != null) {
      return;
    }
    final patient = model.patients
        .where((p) => p.id == widget.initialPatientId)
        .firstOrNull;
    if (patient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El paciente no está disponible con tus permisos actuales.',
          ),
        ),
      );
      return;
    }
    await model.select(patient);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      activity?.load();
    } else {
      activity?.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    activityTimer?.cancel();
    activity?.dispose();
    model.dispose();
    search.dispose();
    historySearch.dispose();
    super.dispose();
  }

  Future<void> create() async {
    // The route can outlive the list while permissions are refreshed. Capture
    // its repository/scope, not the list controller that may be disposed.
    final repository = widget.repository;
    final clinicId = widget.member.clinicId;
    final owners = List<VetOwner>.unmodifiable(model.owners);
    final theme = Theme.of(context);
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => Theme(
          data: theme,
          child: PatientForm(
            owners: owners,
            save: (patient, owner, operation) async {
              try {
                await repository.createPatient(
                  clinicId,
                  patient,
                  owner,
                  operation,
                );
                return null;
              } on FormatException catch (e) {
                return e.message.toString();
              } catch (e) {
                return planActionError(e) ??
                    'No se pudo guardar. Revisa conexión y permisos; '
                        'puedes reintentar con este formulario sin duplicar el registro.';
              }
            },
          ),
        ),
      ),
    );
    if (mounted && saved == true) await model.load();
  }

  Future<void> add(EventKind kind, {bool history = false}) async {
    final patient = model.selected;
    if (patient == null) return;
    final theme = Theme.of(context);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme,
          child: EventForm(
            ai: widget.ai,
            member: widget.member,
            kind: kind,
            history: history,
            patient: patient,
            save: (data, id) async => (await model.add(kind, data, id))
                ? null
                : model.error ?? 'No se pudo guardar.',
          ),
        ),
      ),
    );
  }

  Future<void> reminder(VetOwner owner, PatientEvent event) async {
    final phone = owner.phone.replaceAll(RegExp(r'[\s()+-]'), '');
    if (!RegExp(r'^\d{8,15}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registra un teléfono internacional válido del tutor para abrir WhatsApp.',
          ),
        ),
      );
      return;
    }
    final due = event.data['next_date'];
    final message =
        'Hola ${owner.name}. Recordatorio de ${model.member.clinicName}: ${model.selected!.name} tiene una fecha de ${event.data['type']} registrada para $due. Contáctanos para revisar la indicación y agendar, si corresponde.';
    final uri = Uri.https('wa.me', '/$phone', {'text': message});
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, ?activity]),
    builder: (context, _) {
      final patient = model.selected;
      final snapshot = activity?.snapshot;
      final selectedActivity =
          snapshot != null &&
              activityFilter != null &&
              snapshot.allowed(activityFilter!)
          ? activityFilter
          : null;
      final speciesNames = <String, String>{
        for (final p in model.patients)
          if (p.species.trim().isNotEmpty)
            patientSearchText(p.species): p.species.trim(),
      };
      final selectedSpecies = speciesNames.containsKey(species)
          ? species
          : null;
      final speciesKeys = speciesNames.keys.toList()..sort();
      final matches = model.patients
          .where(
            (p) =>
                (selectedActivity == null ||
                    snapshot!
                        .forPatient(p.id)
                        .any((a) => a.kind == selectedActivity)) &&
                (selectedSpecies == null ||
                    patientSearchText(p.species) == selectedSpecies) &&
                patientSearchText('${p.name} ${p.species}').contains(query),
          )
          .toList();
      VetOwner? owner;
      if (patient != null && model.access.owners) {
        for (final o in model.owners) {
          if (o.id == patient.ownerId) {
            owner = o;
            break;
          }
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pacientes y expedientes',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (model.access.createPatient)
                FilledButton.icon(
                  onPressed: model.busy ? null : create,
                  icon: const Icon(Icons.pets),
                  label: const Text('Nuevo paciente'),
                ),
              OutlinedButton.icon(
                onPressed: model.busy
                    ? null
                    : () async {
                        await model.load();
                        await activity?.load();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
          if (model.busy) const LinearProgressIndicator(),
          if (model.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                model.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (activity != null) ...[
            const SizedBox(height: 16),
            Text(
              snapshot == null
                  ? 'Actividad de pacientes'
                  : 'Actividad · ${snapshot.day} · ${snapshot.timezone}',
            ),
            if (activity!.busy) const LinearProgressIndicator(),
            if (activity!.error != null) Text(activity!.error!),
            if (snapshot != null) ...[
              const Text(
                'Incluye hospitalización activa y atenciones pendientes de días anteriores. Contadores de pacientes cargados, sin duplicados.',
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Todos (${model.patients.length})'),
                      selected: selectedActivity == null,
                      onSelected: (_) => setState(() => activityFilter = null),
                    ),
                    for (final kind in PatientActivityKind.values)
                      if (snapshot.allowed(kind))
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${kind.label} (${snapshot.count(kind, model.patients.map((p) => p.id).toSet())})',
                            ),
                            selected: selectedActivity == kind,
                            onSelected: (_) =>
                                setState(() => activityFilter = kind),
                          ),
                        ),
                  ],
                ),
              ),
              if (!snapshot.hospitalAllowed || !snapshot.appointmentsAllowed)
                const Text(
                  'Solo se muestra actividad de las áreas autorizadas.',
                ),
            ],
          ],
          const SizedBox(height: 16),
          TextField(
            controller: search,
            decoration: const InputDecoration(
              labelText: 'Buscar paciente o especie',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (s) => setState(() => query = patientSearchText(s)),
          ),
          if (model.patients.isEmpty && !model.busy && model.error == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Todavía no hay pacientes registrados en esta clínica.',
              ),
            ),
          if (!model.busy &&
              model.error == null &&
              model.patients.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Todas las especies'),
                    selected: selectedSpecies == null,
                    onSelected: (_) => setState(() => species = null),
                  ),
                  for (final key in speciesKeys)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(speciesNames[key]!),
                        selected: selectedSpecies == key,
                        onSelected: (_) => setState(() => species = key),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${matches.length} coincidencias de ${model.patients.length} pacientes cargados',
            ),
            if (matches.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No hay pacientes que coincidan con la búsqueda y la especie.',
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  search.clear();
                  query = '';
                  species = null;
                  activityFilter = null;
                }),
                child: const Text('Limpiar búsqueda y filtros'),
              ),
            ],
          ],
          for (final p in matches) ...[
            PatientCatalogTile(
              patient: p,
              selected: patient?.id == p.id,
              onTap: model.busy
                  ? null
                  : () {
                      setState(() {
                        historyQuery = '';
                        historySearch.clear();
                        historyKind = null;
                      });
                      model.select(p);
                    },
            ),
            if (snapshot != null)
              for (final item in snapshot.forPatient(p.id))
                ListTile(
                  dense: true,
                  title: Text('${item.kind.label} · ${item.detail}'),
                  subtitle: Text(
                    '${item.kind == PatientActivityKind.hospitalized ? 'Ingreso' : 'Cita'}: ${item.localTime} · ${snapshot.timezone}${item.responsible.isEmpty ? '' : ' · Responsable: ${item.responsible}'}',
                  ),
                  trailing:
                      (widget.onOpenActivity == null ||
                          widget.canOpenActivity?.call(item.destination) ==
                              false)
                      ? null
                      : const Icon(Icons.open_in_new),
                  onTap:
                      (widget.onOpenActivity == null ||
                          widget.canOpenActivity?.call(item.destination) ==
                              false)
                      ? null
                      : () async {
                          await widget.onOpenActivity!(item.destination, p.id);
                          if (mounted) await activity?.load();
                        },
                ),
          ],
          if (patient != null) ...[
            const Divider(height: 32),
            PatientIdentity(patient: patient),
            if (model.access.clinical && !model.busy && model.error == null)
              for (final allergy in model.events.where(
                (e) => e.kind == EventKind.allergy,
              ))
                Text(
                  'Alergia registrada: ${allergy.data['substance']} · ${allergy.data['reaction']}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            if (model.access.owners)
              WorkspacePanel(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: owner == null
                      ? const Text('Tutor pendiente de capturar.')
                      : widget.repository is PatientContactRepository
                      ? PatientContactPanel(
                          key: ValueKey(
                            'contact:${widget.member.userId}:${widget.member.clinicId}:${patient.id}:${owner.id}',
                          ),
                          repository:
                              widget.repository as PatientContactRepository,
                          clinic: widget.member.clinicId,
                          patient: patient.id,
                          patientName: patient.name,
                          onSaved: () async {
                            await model.load();
                            if (mounted) await model.select(patient);
                          },
                        )
                      : ContactActions(
                          owner: {
                            'id': owner.id,
                            'name': owner.name,
                            'phone': owner.phone,
                            'email': owner.email,
                            'address': owner.address,
                          },
                          patientName: patient.name,
                        ),
                ),
              ),
            if (model.access.clinical) ...[
              if (model.access.canAdd(EventKind.soap))
                OutlinedButton.icon(
                  onPressed: model.busy
                      ? null
                      : () => add(EventKind.soap, history: true),
                  icon: const Icon(Icons.history_edu),
                  label: const Text('Registrar historia clínica'),
                ),
              for (final e in patientTimeline(model.events).where(
                (e) =>
                    e.kind == EventKind.soap &&
                    e.data['record_type'] == 'clinical_history',
              ))
                ExpansionTile(
                  title: Text('Historia clínica · ${e.data['date']}'),
                  subtitle: Text(
                    'Registro: ${patientEventTimestamp(context, e.createdAt)} · ${e.createdBy}',
                  ),
                  children: [
                    for (final field in historyFields.entries)
                      if ('${e.data[field.key] ?? ''}'.isNotEmpty)
                        ListTile(
                          title: Text(field.value),
                          subtitle: Text('${e.data[field.key]}'),
                        ),
                  ],
                ),
              PreventiveBooklet(events: model.events),
              if (widget.repository is PreventiveRepository)
                OutlinedButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: const Text(
                    'Abrir carnet · comprobantes y próximas citas',
                  ),
                  onPressed: model.busy
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PreventiveScreen(
                                key: ValueKey(
                                  'booklet-${widget.member.userId}-${widget.member.clinicId}-${patient.id}',
                                ),
                                repository:
                                    widget.repository as PreventiveRepository,
                                clinic: widget.member.clinicId,
                                patient: patient.id,
                                clinicName: widget.member.clinicName,
                              ),
                            ),
                          );
                          if (mounted) await model.select(patient);
                        },
                ),

              if (widget.onOpenClinical != null)
                OutlinedButton(
                  onPressed: model.busy
                      ? null
                      : () async {
                          await widget.onOpenClinical!(patient);
                          if (mounted) await model.select(patient);
                        },
                  child: const Text('Casos clínicos / hoja quirúrgica'),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in EventKind.values)
                    if (model.access.canAdd(kind))
                      OutlinedButton(
                        onPressed: model.busy ? null : () => add(kind),
                        child: Text('Agregar ${kind.label.toLowerCase()}'),
                      ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Historial clínico',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('history-search:${patient.id}'),
                controller: historySearch,
                decoration: const InputDecoration(
                  labelText: 'Buscar por motivo de consulta',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => historyQuery = value),
              ),
              DropdownButtonFormField<EventKind?>(
                key: ValueKey(
                  'history-kind:${patient.id}:${historyKind?.name}',
                ),
                initialValue: historyKind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo de entrada'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Todas las entradas'),
                  ),
                  for (final kind in EventKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (value) => setState(() => historyKind = value),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Más antiguas primero'),
                    selected: historyOldestFirst,
                    onSelected: (value) =>
                        setState(() => historyOldestFirst = value),
                  ),
                  FilterChip(
                    label: const Text('Agrupar por motivo'),
                    selected: historyByReason,
                    onSelected: (value) =>
                        setState(() => historyByReason = value),
                  ),
                ],
              ),
              const Text(
                'Orden por fecha clínica. Fechas preventivas desconocidas: se usa la fecha de registro. El motivo agrupa consultas, sin unir ni modificar documentos.',
              ),
              WeightChart(events: model.events),
              const Divider(height: 32),
              if (model.events.isEmpty && !model.busy)
                const Text('Sin entradas clínicas registradas.'),
              if (model.events.isNotEmpty &&
                  patientTimeline(
                    model.events,
                    query: historyQuery,
                    kind: historyKind,
                  ).isEmpty)
                const Text(
                  'Sin coincidencias para estos filtros; el expediente original se conserva.',
                ),
              for (final event in patientTimeline(
                model.events,
                query: historyQuery,
                kind: historyKind,
                oldestFirst: historyOldestFirst,
                byReason: historyByReason,
              ))
                WorkspacePanel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.kind == EventKind.preventive
                              ? '${event.kind.label} · ${preventiveDateLabel(event.data)}'
                              : '${event.data['record_type'] == 'clinical_history'
                                    ? 'Historia clínica'
                                    : event.data['record_type'] == 'care_discharge'
                                    ? 'Cierre de consulta e indicaciones'
                                    : event.kind.label} · ${event.data['date']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (event.formDocumentId != null ||
                            event.clinicalCaseId != null)
                          Text(
                            'Vinculado a un formato clínico · consulta el documento y sus anexos en Casos clínicos.',
                          ),
                        ...switch (event.kind) {
                          EventKind.soap => [
                            Text('Motivo: ${event.data['reason']}'),
                            for (final pair in <(String, String)>[
                              ('subjective', 'Subjetivo'),
                              ('objective', 'Objetivo'),
                              ('assessment', 'Valoración'),
                              ('plan', 'Plan'),
                            ])
                              if ((event.data[pair.$1] as String).isNotEmpty)
                                Text('${pair.$2}: ${event.data[pair.$1]}'),
                          ],
                          EventKind.weight => [Text('${event.data['kg']} kg')],
                          EventKind.allergy => [
                            Text(
                              '${event.data['substance']} · ${event.data['reaction']}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(event.data['notes'] as String? ?? ''),
                          ],
                          EventKind.preventive => [
                            Text(preventiveOriginLabel(event.data)),
                            if ('${event.data['coverage'] ?? ''}'.isNotEmpty)
                              Text(
                                'Coberturas / tipo: ${event.data['coverage']}',
                              ),
                            Text(
                              '${event.data['type']} · ${event.data['product']}',
                            ),
                            Text('Lote: ${event.data['batch'] ?? 'Pendiente'}'),
                            if (event.data['next_date'] != null) ...[
                              Text('Próxima fecha: ${event.data['next_date']}'),
                              if (owner != null)
                                TextButton.icon(
                                  onPressed: () => reminder(owner!, event),
                                  icon: const Icon(Icons.message_outlined),
                                  label: const Text(
                                    'Preparar recordatorio por WhatsApp',
                                  ),
                                ),
                            ],
                            Text(event.data['notes'] as String? ?? ''),
                          ],
                          EventKind.consent => [
                            Text(event.data['procedure'] as String),
                            Text('Tutor firmante: ${event.data['signer']}'),
                            Text(event.data['text'] as String),
                            SizedBox(
                              height: 120,
                              child: CustomPaint(
                                painter: SignaturePainter(
                                  (event.data['signature'] as List)
                                      .map(
                                        (p) => p == null
                                            ? null
                                            : Offset(
                                                (p[0] as num).toDouble(),
                                                (p[1] as num).toDouble(),
                                              ),
                                      )
                                      .toList(),
                                  Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        },
                        const SizedBox(height: 8),
                        Text(
                          'Registrado: ${patientEventTimestamp(context, event.createdAt)} · Usuario: ${event.createdBy}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Tu rol permite consultar datos generales del paciente. El expediente clínico requiere acceso de MVZ, admin o auxiliar.',
                ),
              ),
          ],
        ],
      );
    },
  );
}
