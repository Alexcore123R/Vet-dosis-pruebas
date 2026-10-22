import 'package:flutter/material.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/form_models.dart';
import '../domain/form_repository.dart';
import 'form_pdf_screen.dart';

// Only server-reported actions are displayed. No job/role fallback.
class DocumentFlowScreen extends StatefulWidget {
  const DocumentFlowScreen({
    super.key,
    required this.repository,
    required this.id,
    required this.edit,
  });
  final FormRepository repository;
  final String id;
  final Future<void> Function(FormDocument, Map<String, dynamic>) edit;
  @override
  State<DocumentFlowScreen> createState() => _DocumentFlowScreenState();
}

class _DocumentFlowScreenState extends State<DocumentFlowScreen> {
  Map<String, dynamic>? flow;
  bool busy = false;
  String? error;
  FormWorkflowRepository get source =>
      widget.repository as FormWorkflowRepository;
  FormDocument get document =>
      FormDocument.read(Map<String, dynamic>.from(flow!['document'] as Map));
  bool can(String action) => !busy && flow?['actions']?[action] == true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      flow = null;
      error = null;
    });
    try {
      final result = await source.documentFlow(widget.id);
      if (result['schema_version'] != 1 ||
          result['mode'] != 'individual_forms' ||
          result['document'] is! Map ||
          result['document']['id'] != widget.id ||
          result['actions'] is! Map ||
          const [
            'edit',
            'select',
            'sign_attention',
            'submit',
            'authorize',
            'preview',
            'capture_tutor',
            'view_pdf',
            'issue',
            'reopen',
            'reject',
          ].any((k) => result['actions'][k] is! bool) ||
          const [
            'people',
            'cases',
            'responsibles',
          ].any((k) => result[k] is! List)) {
        throw StateError('unknown_form_flow');
      }
      final parsed = FormDocument.read(
        Map<String, dynamic>.from(result['document'] as Map),
      );
      if (parsed.revision < 1 ||
          !const {
            'draft',
            'awaiting_authorization',
            'awaiting_tutor',
            'awaiting_review',
            'ready',
            'signed',
          }.contains(parsed.state) ||
          const ['people', 'responsibles'].any(
            (k) => (result[k] as List).any(
              (r) => r is! Map || r['id'] is! String || r['name'] is! String,
            ),
          ) ||
          (result['cases'] as List).any(
            (r) => r is! Map || r['id'] is! String || r['title'] is! String,
          ) ||
          result['field_choices'] is! Map ||
          (result['field_choices'] as Map).values.any(
            (v) =>
                v is! List ||
                v.any(
                  (r) =>
                      r is! Map || r['id'] is! String || r['label'] is! String,
                ),
          )) {
        throw StateError('unknown_form_flow');
      }
      if (mounted) {
        setState(() => flow = result);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo verificar el acceso y la versión del documento. Actualiza antes de continuar.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> entry(
    String title,
    List<RxField> fields,
    String rpc,
    Map<String, dynamic> Function(Map<String, dynamic>) payload, {
    String? review,
  }) async {
    if (busy || flow == null) {
      return;
    }
    final revision = document.revision;
    setState(() => busy = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RxEntryScreen(
            title: title,
            fields: fields,
            reviewText: review,
            submit: (data, operation) async {
              await source.flowAction(rpc, {
                'p_id': widget.id,
                'p_revision': revision,
                'p_operation': operation,
                ...payload(data),
              });
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        await load();
      }
    }
  }

  Map<String, String> options(String key, String label) => {
    for (final r in flow![key] as List) r['id'] as String: '${r[label]}',
  };
  Future<void> previewTutor() async {
    if (!can('preview')) {
      return;
    }
    final revision = document.revision;
    String? failure;
    setState(() => busy = true);
    try {
      final pdf = await source.tutorPreview(widget.id);
      if (!mounted) {
        return;
      }
      final reviewed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => FormPdfScreen(
            pdf: pdf,
            title: 'Revisión del tutor',
            actionLabel: 'Continuar a firma del tutor',
            confirmLabel:
                'El tutor revisó este documento completo y desea continuar a su firma personal.',
            confirm: () async {},
          ),
        ),
      );
      if (reviewed != true || !mounted) {
        return;
      }
      // Refetch after review; no signature against a replaced revision.
      final result = await source.documentFlow(widget.id);
      if (result['document']?['revision'] != revision ||
          result['actions']?['capture_tutor'] != true) {
        throw StateError('document_changed');
      }
      if (!mounted) {
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RxEntryScreen(
            title: 'Firma personal del tutor',
            fields: const [
              RxField(
                'signature',
                'Firma del tutor',
                type: 'signature',
                required: true,
              ),
              RxField(
                'confirmed',
                'El tutor firmó personalmente después de revisar el documento. No se utilizó una firma de perfil ni delegada.',
                type: 'checkbox',
                required: true,
              ),
            ],
            reviewText:
                'El firmante debe ser la persona identificada en el documento. Solo se conserva su número de identificación.',
            submit: (data, operation) async {
              await source.flowAction('form_tutor_capture', {
                'p_id': widget.id,
                'p_revision': revision,
                'p_preview_hash': pdf.hash,
                'p_signature': data['signature'],
                'p_confirmed': data['confirmed'],
                'p_operation': operation,
              });
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        failure =
            'Cambió el documento o el acceso. Revisa de nuevo antes de firmar.';
      }
    } finally {
      if (mounted) {
        await load();
        if (mounted && failure != null) {
          setState(() => error = failure);
        }
      }
    }
  }

  Future<void> reviewPdf() async {
    if (!can('view_pdf')) {
      return;
    }
    final revision = document.revision, issue = can('issue');
    String? failure;
    setState(() => busy = true);
    try {
      final pdf = await widget.repository.pdf(widget.id);
      if (!mounted) {
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FormPdfScreen(
            pdf: pdf,
            title: 'Revisión final del PDF',
            signed: document.state == 'signed',
            actionLabel: 'Emitir y conservar este PDF',
            confirmLabel:
                'Revisé este PDF completo y confirmo su emisión. Las firmas y la autorización corresponden a las personas indicadas.',
            confirm: issue
                ? () async {
                    await widget.repository.finalize(
                      widget.id,
                      revision,
                      pdf.hash,
                    );
                  }
                : null,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        failure = 'No se pudo verificar el PDF o su autorización.';
      }
    } finally {
      if (mounted) {
        await load();
        if (mounted && failure != null) {
          setState(() => error = failure);
        }
      }
    }
  }

  String reviewedContent() {
    final d = document;
    return ((d.snapshot['schema']?['fields'] as List?) ?? [])
        .where((f) => f['type'] != 'signature')
        .map((f) {
          dynamic value = d.values[f['id']];
          if (f['id'] == 'patient') {
            value = d.snapshot['patient']?['name'];
          }
          if (f['id'] == 'owner') {
            value = d.snapshot['owner']?['name'];
          }
          if (f['type'] == 'person') {
            final choices = (flow!['field_choices']?[f['id']] as List?) ?? [];
            value =
                choices
                    .where((r) => r['id'] == value)
                    .map((r) => r['label'])
                    .firstOrNull ??
                value;
          }
          if (value is bool) {
            value = value ? 'Sí' : 'No';
          }
          return "${f['label']}: ${value == null || value == '' ? 'Sin captura' : value}";
        })
        .join('\n');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Revisión y firmas'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (flow != null) ...[
          Text(
            '${document.snapshot['schema']?['title'] ?? 'Documento'} · Versión ${document.revision}',
          ),
          Text(
            'Estado: ${const {'draft': 'Borrador', 'awaiting_authorization': 'Pendiente de autorización del MVZ', 'awaiting_tutor': 'Pendiente de firma del tutor', 'awaiting_review': 'Pendiente de revisar PDF', 'ready': 'PDF listo para emitir', 'signed': 'Emitido'}[document.state] ?? document.state}',
          ),
          Text(
            'Paciente: ${document.snapshot['patient']?['name'] ?? 'Paciente vinculado'}',
          ),
          Text(
            'MVZ responsable: ${document.values['mvz_name']} · ${document.values['mvz_license']}',
          ),
          Text(
            'Elaboración: ${flow!['authorship']?['name'] ?? 'Firma pendiente'}',
          ),
          Text(
            'Atención o explicación: ${flow!['attention']?['name'] ?? 'Firma pendiente'}',
          ),
          const Text(
            'Cada persona firma desde su propia cuenta. La autorización del MVZ se registra por separado y no utiliza su firma guardada.',
          ),
          if (can('select'))
            OutlinedButton(
              onPressed: () => entry(
                'Quién realizó la atención o explicación',
                [
                  RxField(
                    'actor',
                    'Persona que realizará su propia firma',
                    type: 'select',
                    options: options('people', 'name'),
                    required: true,
                  ),
                  if (document.snapshot['clinical'] == true)
                    RxField(
                      'case',
                      'Caso clínico ya registrado',
                      type: 'select',
                      options: options('cases', 'title'),
                      required: true,
                    ),
                ],
                'form_attention_select',
                (v) => {'p_actor': v['actor'], 'p_case': v['case']},
                review:
                    'Selecciona antes de firmar. Cambiar esta selección invalida las firmas anteriores. En consentimientos, la firma acredita su explicación; no afirma que el procedimiento ya ocurrió.',
              ),
              child: const Text('Seleccionar persona y caso'),
            ),
          if (can('edit'))
            OutlinedButton(
              onPressed: () async {
                setState(() => busy = true);
                try {
                  await widget.edit(
                    document,
                    Map<String, dynamic>.from(
                      flow!['field_choices'] as Map? ?? {},
                    ),
                  );
                } finally {
                  if (mounted) {
                    await load();
                  }
                }
              },
              child: const Text('Editar contenido / firma de elaboración'),
            ),
          if (can('sign_attention'))
            OutlinedButton(
              onPressed: () => entry(
                'Mi atención o explicación',
                const [
                  RxField('name', 'Tu nombre completo', required: true),
                  RxField(
                    'observed',
                    'Fecha y hora reales',
                    type: 'local_instant',
                    required: true,
                  ),
                  RxField(
                    'signature',
                    'Tu firma personal',
                    type: 'signature',
                    required: true,
                  ),
                  RxField(
                    'confirmed',
                    'Confirmo que realicé la atención o explicación indicada y firmo con mi propia identidad.',
                    type: 'checkbox',
                    required: true,
                  ),
                ],
                'form_attention_sign',
                (v) => {
                  'p_name': v['name'],
                  'p_observed': v['observed'],
                  'p_signature': v['signature'],
                  'p_confirmed': v['confirmed'],
                },
              ),
              child: const Text('Firmar mi atención / explicación'),
            ),
          if (can('submit'))
            FilledButton(
              onPressed: () => entry(
                'Solicitar revisión',
                const [
                  RxField(
                    'confirmed',
                    'Revisé el contenido y las personas que firmaron esta versión.',
                    type: 'checkbox',
                    required: true,
                  ),
                ],
                'form_review_submit',
                (v) => {
                  'p_authorship': flow!['authorship']['id'],
                  'p_attention': flow!['attention']['id'],
                },
              ),
              child: const Text('Enviar al MVZ responsable'),
            ),
          if (can('authorize')) ...[
            Text('Clínica: ${document.snapshot['clinic_name'] ?? ''}'),
            Text('Membrete: ${document.branding['header'] ?? ''}'),
            SelectableText(reviewedContent()),
            ...((document.snapshot['schema']?['clauses'] as List?) ?? []).map(
              (c) => Text('${c['text']}'),
            ),
            FilledButton(
              onPressed: () => entry(
                'Autorización individual',
                const [
                  RxField(
                    'confirmed',
                    'Revisé el contenido completo de esta versión, sus firmas y autorizo este documento como MVZ responsable.',
                    type: 'checkbox',
                    required: true,
                  ),
                ],
                'form_authorize_individual',
                (v) => {'p_confirmed': v['confirmed']},
              ),
              child: const Text('Autorizar esta versión'),
            ),
          ],
          if (can('capture_tutor'))
            FilledButton(
              onPressed: previewTutor,
              child: const Text('Revisar con el tutor y recoger su firma'),
            ),
          if (can('view_pdf'))
            FilledButton(
              onPressed: reviewPdf,
              child: Text(
                can('issue')
                    ? 'Revisar PDF y emitir'
                    : 'Ver PDF pendiente de emisión',
              ),
            ),
          if (can('reject'))
            OutlinedButton(
              onPressed: () => entry(
                'Devolver para corrección',
                const [RxField('reason', 'Motivo', required: true)],
                'form_review_reject',
                (v) => {'p_reason': v['reason']},
              ),
              child: const Text('Solicitar corrección'),
            ),
          if (can('reopen'))
            OutlinedButton(
              onPressed: () => entry(
                'Reabrir para corregir',
                [
                  RxField(
                    'responsible',
                    'MVZ responsable',
                    type: 'select',
                    options: options('responsibles', 'name'),
                    required: true,
                  ),
                  const RxField(
                    'reason',
                    'Motivo de la corrección',
                    required: true,
                  ),
                ],
                'form_document_reopen',
                (v) => {
                  'p_responsible': v['responsible'],
                  'p_reason': v['reason'],
                },
                review:
                    'Se conservará la evidencia anterior. Esta revisión necesitará firmas y autorización nuevas.',
              ),
              child: const Text('Reabrir / cambiar responsable'),
            ),
        ],
      ],
    ),
  );
}
