import '../../prescribing/domain/prescribing_repository.dart';
import '../../prescribing/presentation/prescribing_screen.dart';
import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/form_repository.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../presentation/form_pdf_screen.dart';
import 'clinical_models.dart';
import 'clinical_repository.dart';
import 'clinical_view_model.dart';
import 'clinical_vitals_screen.dart';
import 'vitals_models.dart';

class ClinicalScreen extends StatefulWidget {
  const ClinicalScreen({
    super.key,
    required this.repository,
    required this.forms,
    required this.member,
    this.patientId,
    this.prescribing,
  });
  final ClinicalRepository repository;
  final FormRepository forms;
  final ClinicMembership member;
  final String? patientId;
  final PrescribingRepository? prescribing;
  @override
  State<ClinicalScreen> createState() => _ClinicalScreenState();
}

class _ClinicalScreenState extends State<ClinicalScreen> {
  late final model = ClinicalViewModel(
    widget.repository,
    widget.member.clinicId,
    widget.patientId,
  );
  @override
  void initState() {
    super.initState();
    model.load();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> original(
    ClinicalCase c, {
    String? documentId,
    String? title,
  }) async {
    try {
      final id = documentId ?? c.documentId;
      if (id == null) {
        message('Este caso todavía no tiene un documento firmado.');
        return;
      }
      final pdf = await widget.forms.pdf(id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FormPdfScreen(
            pdf: pdf,
            title: title ?? 'Documento clínico original',
            signed: true,
          ),
        ),
      );
    } catch (_) {
      message('No se pudo abrir el PDF original.');
    }
  }

  bool registering = false;
  Future<void> registerCase() async {
    if (registering || model.busy) {
      return;
    }
    registering = true;
    try {
      await model.load();
      if (!mounted || !model.canCreate) {
        return;
      }
      final source = widget.repository as ClinicalCaseRegistrationRepository;
      String? created;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RxEntryScreen(
            title: 'Registrar caso',
            reviewText:
                'Registra el contexto inicial. Elegir al MVZ no acredita que atendió ni autoriza procedimientos. No se crea PDF ni se rellenan mediciones o SOAP.',
            fields: [
              RxField(
                'patient_id',
                'Paciente',
                type: 'select',
                options: {
                  for (final r
                      in model
                          .rows('patients')
                          .where(
                            (r) =>
                                widget.patientId == null ||
                                r['id'] == widget.patientId,
                          ))
                    r['id'] as String: r['name'] as String,
                },
                required: true,
              ),
              RxField(
                'responsible_id',
                'MVZ responsable seleccionado',
                type: 'select',
                options: {
                  for (final r in model.rows('responsibles'))
                    r['id'] as String: '${r['name']} · ${r['license']}',
                },
                required: true,
              ),
              const RxField(
                'kind',
                'Contexto del caso (no acredita realización)',
                type: 'select',
                options: {
                  'clinical_history': 'Atención clínica',
                  'surgical_sheet': 'Cirugía',
                  'surgical_risk': 'Evaluación prequirúrgica',
                },
                required: true,
              ),
              const RxField(
                'clinical_date',
                'Fecha clínica',
                type: 'local_date',
                required: true,
              ),
              const RxField('reason', 'Motivo de atención', required: true),
              const RxField('notes', 'Notas iniciales (opcional)'),
            ],
            submit: (data, operation) async {
              created = await source.registerCase(
                widget.member.clinicId,
                data,
                operation,
              );
            },
          ),
        ),
      );
      if (mounted) {
        await model.load(caseId: created);
      }
    } finally {
      registering = false;
    }
  }

  Future<void> append(String mode, {Map<String, dynamic>? correction}) async {
    final c = model.selected!.caseData;
    if (model.permissionsKnown) {
      await appendPermitted(mode, correction: correction);
      return;
    }
    try {
      final staff = await widget.forms.staff(widget.member.clinicId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ClinicalEntryScreen(
            repository: widget.repository,
            member: widget.member,
            caseData: c,
            mode: mode,
            staff: staff,
            correction: correction,
          ),
        ),
      );
      if (mounted) await model.load(caseId: c.id);
    } catch (_) {
      message('No se pudo abrir la captura.');
    }
  }

  Future<void> appendPermitted(
    String mode, {
    Map<String, dynamic>? correction,
  }) async {
    final c = model.selected!.caseData;
    await model.load(caseId: c.id);
    if (!mounted) {
      return;
    }
    final capability = mode == 'observation'
        ? (correction == null ? 'observe' : 'correct')
        : mode == 'grant'
        ? 'authorize'
        : mode == 'bind'
        ? 'bind'
        : 'act';
    if (!model.can(capability)) {
      message('La autorización cambió. Actualiza antes de continuar.');
      return;
    }
    final observation = mode == 'observation',
        grant = mode == 'grant',
        binding = mode == 'bind';
    final members = {
      for (final r in model.rows('members'))
        r['id'] as String: r['label'] as String,
    };
    final mapped = {
      for (final r in model.rows('bindings'))
        r['scope'] as String: clinicalScopes[r['scope']]!,
    };
    final fields = <RxField>[
      if (observation && correction == null)
        RxField(
          'kind',
          'Medición que realizaste',
          type: 'select',
          options: {
            for (final e in observationNames.entries)
              e.key: '${e.value} (${observationUnits[e.key]})',
          },
          required: true,
        ),
      if (observation)
        RxField(
          'value',
          correction == null
              ? 'Valor (unidad indicada por la medición)'
              : 'Nuevo valor (${correction['unit']})',
          required: true,
        ),
      if (!observation)
        RxField(
          'scope',
          'Procedimiento',
          type: 'select',
          options: binding
              ? clinicalScopes
              : grant
              ? mapped
              : {
                  for (final scope in model.actScopes)
                    scope: clinicalScopes[scope]!,
                },
          required: true,
        ),
      if (grant)
        RxField(
          'person',
          'Persona autorizada para este caso',
          type: 'select',
          options: members,
          required: true,
        ),
      if (binding) ...[
        RxField(
          'procedure',
          'Tipo de procedimiento configurado',
          type: 'select',
          options: {
            for (final r in model.rows('procedures'))
              r['id'] as String: r['name'] as String,
          },
          required: true,
        ),
        const RxField(
          'professional',
          'Habilitación profesional requerida',
          type: 'select',
          options: {'true': 'Sí', 'false': 'No (solo mediciones)'},
          required: true,
        ),
        const RxField(
          'source',
          'Fuente de esta política de la clínica',
          required: true,
        ),
        const RxField(
          'reason',
          'Motivo de la configuración o cambio',
          required: true,
        ),
      ] else ...[
        RxField(
          'at',
          grant
              ? 'Vigente hasta'
              : 'Fecha y hora reales de tu medición o actuación',
          type: 'local_instant',
          required: true,
        ),
        if (!grant)
          RxField(
            'notes',
            observation
                ? 'Observaciones (opcional)'
                : 'Actuación que realizaste y hallazgos',
            required: !observation,
          ),
      ],
      if (correction != null)
        const RxField('reason', 'Motivo de la corrección', required: true),
    ];
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RxEntryScreen(
          title: binding
              ? 'Configurar procedimiento'
              : grant
              ? 'Autorizar en este caso'
              : observation
              ? 'Anexar mi medición'
              : 'Anexar mi actuación',
          fields: fields,
          reviewText: binding
              ? 'Esta configuración no habilita personas ni concede permisos operativos. Cirugía, anestesia y evaluación conservan la política profesional vigente.'
              : grant
              ? 'Esta autorización se limita al caso y no concede habilitación profesional, permisos operativos, recetas ni controlados.'
              : 'Se registra tu cuenta como quien realizó la entrada. Los campos no capturados permanecen vacíos; no se interpretan como normales.',
          submit: (data, operation) async {
            if (binding) {
              await (widget.repository as ClinicalPermissionRepository)
                  .bindScope(
                    c.id,
                    data['scope'],
                    data['procedure'],
                    data['professional'] == 'true',
                    data['source'],
                    data['reason'],
                  );
            } else if (grant) {
              await widget.repository.authorize(
                c.id,
                data['person'],
                data['scope'],
                data['at'],
                operation,
              );
            } else if (observation) {
              final kind = correction?['kind'] ?? data['kind'];
              await widget.repository.observation(
                c.id,
                validateObservation({
                  'kind': kind,
                  'value': data['value'],
                  'unit': observationUnits[kind],
                  'observed_at': data['at'],
                  'performed_by': widget.member.userId,
                  'notes': data['notes'] ?? '',
                  if (correction != null) 'replaces_id': correction['id'],
                  if (correction != null) 'correction_reason': data['reason'],
                }),
                operation,
              );
            } else {
              await widget.repository.act(
                c.id,
                data['scope'],
                data['notes'],
                widget.member.userId,
                data['at'],
                operation,
              );
            }
          },
        ),
      ),
    );
    if (mounted) {
      await model.load(caseId: c.id);
    }
  }

  String? latestWeight(ClinicalBundle bundle) {
    for (final row in bundle.observations.reversed) {
      if (row['kind'] == 'weight' && row['value'] != null) {
        return row['value'].toString();
      }
    }
    return null;
  }

  Future<void> openVitals() async {
    final selected = model.selected;
    if (selected == null) return;
    await model.load(caseId: selected.caseData.id);
    if (!mounted || model.selected == null) return;
    if (model.permissionsKnown && !model.can('observe')) {
      message('La autorización cambió. Actualiza antes de continuar.');
      return;
    }
    final bundle = model.selected!;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicalVitalsScreen(
          repository: widget.repository,
          member: widget.member,
          caseData: bundle.caseData,
          latestWeight: latestWeight(bundle),
        ),
      ),
    );
    if (saved == true && mounted) {
      await model.load(caseId: bundle.caseData.id);
    }
  }

  Future<void> revoke(Map<String, dynamic> grant) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revocar autorización'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Motivo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      await widget.repository.revoke(grant['id'], reason, newOperationId());
      if (mounted) await model.load(caseId: model.selected!.caseData.id);
    } catch (_) {
      message('No se revocó. Actualiza antes de reintentar.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Casos clínicos y actuaciones')),
    body: ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final b = model.selected;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Los documentos firmados conservan su versión original y aparecen aquí como evidencia del expediente. Mediciones y actuaciones se registran por separado y se anexan al caso. ASA y EKG son capturas profesionales, sin interpretación automática.',
            ),
            OutlinedButton.icon(
              onPressed: model.busy
                  ? null
                  : () => model.load(caseId: b?.caseData.id),
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
            if (model.canCreate)
              FilledButton.icon(
                onPressed: registerCase,
                icon: const Icon(Icons.add),
                label: const Text('Registrar caso sin PDF'),
              ),
            if (model.busy) const LinearProgressIndicator(),
            if (model.error != null) Text(model.error!),
            if (model.cases.isEmpty && !model.busy)
              Text(
                model.permissionsKnown
                    ? 'Sin casos disponibles para este acceso. Los formatos no crean consultas automáticamente.'
                    : 'Sin casos disponibles. Crea y confirma un formato clínico en Formatos.',
              ),
            for (final c in model.cases)
              ListTile(
                title: Text('${c.patientName} · ${c.title}'),
                subtitle: Text(
                  '${c.data['clinical_date']} · ${c.data['reason']}',
                ),
                selected: b?.caseData.id == c.id,
                onTap: model.busy ? null : () => model.load(caseId: c.id),
              ),
            if (b != null) ...[
              const Divider(),
              Text(
                b.caseData.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final s in b.staff) Text('${s['role']}: ${s['person_id']}'),
              if (b.caseData.data['asa'] != null)
                Text('ASA: ${b.caseData.data['asa']}'),
              if (b.caseData.data['ekg'] != null)
                Text('EKG: ${b.caseData.data['ekg']}'),
              if (model.permissionsKnown)
                ...model
                    .rows('documents')
                    .map(
                      (d) => TextButton(
                        onPressed: model.busy
                            ? null
                            : () => original(
                                b.caseData,
                                documentId: d['id'],
                                title: d['title'],
                              ),
                        child: Text(
                          '${d['is_original'] == true ? 'Original firmado' : 'Documento firmado'} · ${d['title']}',
                        ),
                      ),
                    )
              else
                TextButton(
                  onPressed: model.busy ? null : () => original(b.caseData),
                  child: const Text('Ver PDF original firmado'),
                ),
              if (model.permissionsKnown
                  ? model.can('observe') || model.can('act')
                  : widget.member.role != ClinicRole.admin)
                Wrap(
                  spacing: 8,
                  children: [
                    if (!model.permissionsKnown || model.can('observe'))
                      FilledButton.icon(
                        onPressed: model.busy ? null : openVitals,
                        icon: const Icon(Icons.monitor_heart_outlined),
                        label: const Text('Registrar constantes'),
                      ),
                    if (!model.permissionsKnown || model.can('observe'))
                      OutlinedButton(
                        onPressed: model.busy
                            ? null
                            : () => append('observation'),
                        child: const Text('Anexar medición individual'),
                      ),
                    if (!model.permissionsKnown || model.can('act'))
                      OutlinedButton(
                        onPressed: model.busy ? null : () => append('act'),
                        child: const Text('Anexar actuación'),
                      ),
                  ],
                ),
              if (widget.prescribing != null)
                OutlinedButton(
                  onPressed: model.busy
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Medicación del caso'),
                                ),
                                body: SingleChildScrollView(
                                  padding: const EdgeInsets.all(20),
                                  child: PrescribingScreen(
                                    repository: widget.prescribing!,
                                    clinical: widget.repository,
                                    forms: widget.forms,
                                    member: widget.member,
                                    patientId: b.caseData.patientId,
                                    initialCase: b.caseData.id,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                  child: const Text('Registro único de medicación / recetas'),
                ),
              const Text(
                'Las aplicaciones de esta hoja se consultan en el registro único de medicación del caso.',
              ),
              const SizedBox(height: 12),
              Text(
                'Constantes estructuradas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (b.vitals.isEmpty)
                const Text(
                  'Todavía no hay conjuntos de constantes registrados.',
                ),
              for (final v in b.vitals.reversed.take(10))
                ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: Text(
                    [
                      if (v['fc'] != null) 'FC ${v['fc']} lpm',
                      if (v['fr'] != null) 'FR ${v['fr']} rpm',
                      if (v['temperature'] != null)
                        'Temp ${v['temperature']} °C',
                      if (v['tllc'] != null) 'TLLC ${v['tllc']} s',
                    ].join(' · '),
                  ),
                  subtitle: Text(
                    [
                      if (v['bp_systolic'] != null)
                        'PA ${v['bp_systolic']}/${v['bp_diastolic']} mmHg · PAM ${v['pam']} mmHg',
                      if (v['mucosa_color'] != null)
                        'Mucosas: ${vitalMucosaColors[v['mucosa_color']] ?? v['mucosa_color']}',
                      if (v['mucosa_humidity'] != null)
                        'Humedad: ${vitalMucosaHumidity[v['mucosa_humidity']] ?? v['mucosa_humidity']}',
                      '${v['observed_at']}',
                      if ((v['notes']?.toString() ?? '').isNotEmpty)
                        '${v['notes']}',
                    ].join('\n'),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Mediciones individuales',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final o in b.observations)
                ListTile(
                  title: Text(
                    '${observationNames[o['kind']]}: ${o['value']} ${o['unit']}',
                  ),
                  subtitle: Text(
                    '${o['observed_at']}\nRealizó: ${o['performed_by']} · Registró: ${o['recorded_by']}\nServidor: ${o['created_at']}\n${o['notes']}\n${o['replaces_id'] == null ? '' : 'Corrección de: ${o['replaces_id']} · ${o['correction_reason']}'}${b.observations.any((x) => x['replaces_id'] == o['id']) ? ' · Sustituida por corrección' : ''}',
                  ),
                ),
              if (model.permissionsKnown
                  ? model.can('correct')
                  : widget.member.role == ClinicRole.mvz &&
                        b.caseData.responsibleId == widget.member.userId)
                for (final o in b.observations.where(
                  (o) =>
                      !b.observations.any((x) => x['replaces_id'] == o['id']),
                ))
                  TextButton(
                    onPressed: model.busy
                        ? null
                        : () => append('observation', correction: o),
                    child: Text(
                      'Corregir ${observationNames[o['kind']]} · ${o['observed_at']}',
                    ),
                  ),
              Text(
                'Actuaciones',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final a in b.acts)
                ListTile(
                  title: Text('${clinicalScopes[a['scope']]} · ${a['notes']}'),
                  subtitle: Text(
                    '${a['observed_at']}\nRealizó: ${a['performed_by']} · Registró: ${a['recorded_by']}\nServidor: ${a['created_at']}',
                  ),
                ),
              Text(
                'Procedimientos autorizados',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Estos permisos no conceden emisión de recetas ni validación de fármacos controlados.',
              ),
              if (model.permissionsKnown && model.can('bind'))
                TextButton(
                  onPressed: () => append('bind'),
                  child: const Text(
                    'Configurar tipo de procedimiento del caso',
                  ),
                ),
              if (model.permissionsKnown
                  ? model.can('authorize')
                  : widget.member.role == ClinicRole.mvz &&
                        b.caseData.responsibleId == widget.member.userId)
                TextButton(
                  onPressed: model.busy ? null : () => append('grant'),
                  child: const Text('Autorizar persona y procedimiento'),
                ),
              for (final a in b.authorizations)
                ListTile(
                  title: Text(
                    '${clinicalScopes[a['scope']]} · ${a['person_id']}',
                  ),
                  subtitle: Text(
                    'Hasta: ${a['valid_until']} · ${a['revoked'] == null ? 'Consultar vigencia por fecha' : 'Revocada: ${a['revoked']['reason']}'}',
                  ),
                  trailing:
                      a['revoked'] == null &&
                          (model.permissionsKnown
                              ? model.can('revoke')
                              : widget.member.role == ClinicRole.mvz &&
                                    b.caseData.responsibleId ==
                                        widget.member.userId)
                      ? IconButton(
                          onPressed: model.busy ? null : () => revoke(a),
                          icon: const Icon(Icons.block),
                          tooltip: 'Revocar',
                        )
                      : null,
                ),
            ],
          ],
        );
      },
    ),
  );
}

class ClinicalEntryScreen extends StatefulWidget {
  const ClinicalEntryScreen({
    super.key,
    required this.repository,
    required this.member,
    required this.caseData,
    required this.mode,
    required this.staff,
    this.correction,
  });
  final ClinicalRepository repository;
  final ClinicMembership member;
  final ClinicalCase caseData;
  final String mode;
  final List<Map<String, dynamic>> staff;
  final Map<String, dynamic>? correction;
  @override
  State<ClinicalEntryScreen> createState() => _ClinicalEntryScreenState();
}

class _ClinicalEntryScreenState extends State<ClinicalEntryScreen> {
  late String kind = widget.correction?['kind'] ?? 'fc';
  String scope = 'evaluacion', correctionReason = '';
  late String person = widget.member.userId;
  late String instant = widget.correction == null
      ? DateTime.now().toUtc().toIso8601String()
      : DateTime.parse(
          widget.correction!['observed_at'],
        ).toUtc().toIso8601String();
  String value = '',
      notes = '',
      until = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 12))
          .toIso8601String();
  bool busy = false;
  String? error;
  String operation = newOperationId(), lastPayload = '';
  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final payload =
          '$kind|$scope|$person|$instant|$value|$notes|$until|$correctionReason';
      if (lastPayload.isNotEmpty && lastPayload != payload) {
        operation = newOperationId();
      }
      lastPayload = payload;
      if (widget.mode == 'observation') {
        await widget.repository.observation(widget.caseData.id, {
          'kind': kind,
          'value': value,
          'unit': observationUnits[kind],
          'observed_at': instant,
          'performed_by': person,
          'notes': notes,
          if (widget.correction != null)
            'replaces_id': widget.correction!['id'],
          if (widget.correction != null) 'correction_reason': correctionReason,
        }, operation);
      } else if (widget.mode == 'grant') {
        await widget.repository.authorize(
          widget.caseData.id,
          person,
          scope,
          until,
          operation,
        );
      } else {
        if (notes.trim().isEmpty) {
          throw const FormatException('Describe la actuación.');
        }
        await widget.repository.act(
          widget.caseData.id,
          scope,
          notes,
          person,
          instant,
          operation,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se guardó. Revisa autorización, persona, hora y conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final observation = widget.mode == 'observation',
        grant = widget.mode == 'grant';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          grant
              ? 'Autorizar procedimiento'
              : observation
              ? 'Anexar medición'
              : 'Anexar actuación',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Cada registro conserva quién realizó el acto, quién lo capturó y la hora del servidor. Se anexa al caso; no se sobrescribe.',
          ),
          if (observation)
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Medición'),
              items: [
                for (final e in observationNames.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text('${e.value} (${observationUnits[e.key]})'),
                  ),
              ],
              onChanged: busy || widget.correction != null
                  ? null
                  : (v) => setState(() => kind = v!),
            ),
          if (!observation)
            DropdownButtonFormField<String>(
              initialValue: scope,
              decoration: const InputDecoration(labelText: 'Procedimiento'),
              items: [
                for (final e in clinicalScopes.entries.where(
                  (e) => grant || e.key != 'observaciones',
                ))
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: busy ? null : (v) => setState(() => scope = v!),
            ),
          DropdownButtonFormField<String>(
            initialValue: widget.staff.any((p) => p['id'] == person)
                ? person
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: grant ? 'Persona autorizada' : 'Quién realizó',
            ),
            items: [
              for (final p in widget.staff.where(
                (p) =>
                    grant ||
                    widget.member.role == ClinicRole.mvz ||
                    p['id'] == widget.member.userId,
              ))
                DropdownMenuItem(
                  value: p['id'] as String,
                  child: Text('${p['label']} · ${p['role']}'),
                ),
            ],
            onChanged: busy ? null : (v) => setState(() => person = v!),
          ),
          TextFormField(
            initialValue: grant ? until : instant,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: grant
                  ? 'Vigente hasta (UTC)'
                  : 'Fecha y hora observada (UTC)',
              helperText: 'AAAA-MM-DDTHH:MM:SSZ',
            ),
            onChanged: (v) {
              if (grant) {
                until = v;
              } else {
                instant = v;
              }
            },
          ),
          if (observation)
            TextFormField(
              enabled: !busy,
              decoration: InputDecoration(
                labelText: 'Valor (${observationUnits[kind]})',
              ),
              onChanged: (v) => value = v,
            ),
          if (!grant)
            TextFormField(
              enabled: !busy,
              maxLines: null,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: observation
                    ? 'Observaciones'
                    : 'Actuación y hallazgos',
              ),
              onChanged: (v) => notes = v,
            ),
          if (widget.correction != null)
            TextFormField(
              enabled: !busy,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Motivo de corrección',
              ),
              onChanged: (v) => correctionReason = v,
            ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? 'Guardando…'
                  : grant
                  ? 'Autorizar'
                  : 'Guardar entrada anexa',
            ),
          ),
        ],
      ),
    );
  }
}
