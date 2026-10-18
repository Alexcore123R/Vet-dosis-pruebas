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
  });
  final String? initialPatientId;
  final PatientRepository repository;
  final ClinicMembership member;
  final Future<void> Function(VetPatient)? onOpenClinical;
  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  late final PatientViewModel model;
  final search = TextEditingController();
  String query = '';
  String? species;
  @override
  void initState() {
    super.initState();
    model = PatientViewModel(widget.repository, widget.member);
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
  void dispose() {
    model.dispose();
    search.dispose();
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

  Future<void> add(EventKind kind) async {
    final patient = model.selected;
    if (patient == null) return;
    final theme = Theme.of(context);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme,
          child: EventForm(
            kind: kind,
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
        'Hola ${owner.name}. Recordatorio de ${model.member.clinicName}: ${model.selected!.name} tiene ${event.data['type']} programada para $due. Contáctanos para confirmar su cita.';
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
    listenable: model,
    builder: (context, _) {
      final patient = model.selected;
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
                onPressed: model.busy ? null : model.load,
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
                }),
                child: const Text('Limpiar búsqueda y filtros'),
              ),
            ],
          ],
          for (final p in matches)
            PatientCatalogTile(
              patient: p,
              selected: patient?.id == p.id,
              onTap: model.busy ? null : () => model.select(p),
            ),
          if (patient != null) ...[
            const Divider(height: 32),
            PatientIdentity(patient: patient),
            if (model.access.owners)
              WorkspacePanel(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: owner == null
                      ? const Text('Tutor pendiente de capturar.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tutor: ${owner.name}'),
                            if (owner.phone.isNotEmpty)
                              Text('Teléfono: ${owner.phone}'),
                            if (owner.email.isNotEmpty)
                              Text('Correo: ${owner.email}'),
                            if (owner.address.isNotEmpty)
                              Text('Dirección: ${owner.address}'),
                          ],
                        ),
                ),
              ),
            if (model.access.clinical) ...[
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
              WeightChart(events: model.events),
              const Divider(height: 32),
              if (model.events.isEmpty && !model.busy)
                const Text('Sin entradas clínicas registradas.'),
              for (final event in model.events.reversed)
                WorkspacePanel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${event.kind.label} · ${event.data['date']}',
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
