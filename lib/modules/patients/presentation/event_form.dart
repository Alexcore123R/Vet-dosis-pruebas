import '../../core/presentation/unsaved_form_scope.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../domain/patient_models.dart';
import '../domain/clinical_record_fields.dart';
import '../domain/preventive_coverage.dart';
import '../application/voice_dictation.dart';
import 'signature_pad.dart';
import 'patient_view_model.dart';

class EventForm extends StatefulWidget {
  const EventForm({
    super.key,
    required this.kind,
    required this.patient,
    required this.save,
    this.voice,
    this.history = false,
  });
  final EventKind kind;
  final VetPatient patient;
  final Future<String?> Function(Map<String, dynamic>, String) save;
  final VoiceDictation? voice;
  final bool history;
  @override
  State<EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<EventForm> {
  final exit = FormExitController();
  late String originalFields;
  String get fieldFingerprint =>
      jsonEncode({for (final e in fields.entries) e.key: e.value.text});
  bool get dirty =>
      fieldFingerprint != originalFields ||
      signature.isNotEmpty ||
      accepted ||
      reviewed ||
      type != 'vacuna' ||
      origin != null ||
      precision != 'exact' ||
      components.isNotEmpty;
  final fields = <String, TextEditingController>{};
  final components = <String>{};
  late final VoiceDictation voice;
  String operationId = newOperationId();
  Map<String, dynamic>? attempted;
  List<List<double>?> signature = [];
  int signatureRevision = 0;
  bool accepted = false, busy = false, reviewed = false, listening = false;
  String type = 'vacuna', target = 'subjective';
  String? error;
  final registrationDate = DateTime.now().toIso8601String().substring(0, 10);
  String? origin;
  String precision = 'exact';
  @override
  void initState() {
    super.initState();
    voice = widget.voice ?? DeviceVoiceDictation();
    for (final k in [
      'date',
      'reason',
      'subjective',
      'objective',
      'assessment',
      'plan',
      'kg',
      'substance',
      'reaction',
      'notes',
      'product',
      'batch',
      'next_date',
      'procedure',
      'text',
      'signer',
      ...historyFields.keys,
      'coverage_other',
      'coverage',
      'date_description',
      'performer',
      'informant',
      'evidence_reference',
      'next_date_by',
    ]) {
      fields[k] = TextEditingController();
    }
    fields['date']!.text = DateTime.now().toIso8601String().substring(0, 10);
    if (widget.kind == EventKind.preventive) fields['date']!.clear();
    originalFields = fieldFingerprint;
    for (final c in fields.values) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    exit.dispose();
    voice.stop().catchError((_) {});
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> toggleVoice() async {
    try {
      await _toggleVoice();
    } catch (_) {
      if (mounted) {
        setState(() {
          listening = false;
          error =
              'El servicio de voz no está disponible. Puedes escribir la nota.';
        });
      }
    }
  }

  Future<void> _toggleVoice() async {
    if (listening) {
      await voice.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    setState(() => listening = true);
    final original = fields[target]!.text;
    final chosen = target;
    final ready = await voice.start(
      (text) {
        if (mounted) {
          setState(() {
            fields[chosen]!.text = [
              original,
              text,
            ].where((s) => s.isNotEmpty).join('\n');
            reviewed = false;
          });
        }
      },
      (message) {
        if (mounted) {
          setState(() {
            error = message;
            listening = false;
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        listening = ready;
        if (!ready) {
          error ??= 'El dictado no está disponible. Puedes escribir la nota.';
        }
      });
    }
  }

  Future<void> save() async {
    if (busy || listening) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final raw = <String, dynamic>{
        for (final entry in fields.entries) entry.key: entry.value.text,
        'type': type,
        'species_template': widget.patient.species,
        'signature': signature,
        'accepted': accepted,
      };
      if (widget.history) {
        raw['record_type'] = 'clinical_history';
        raw['subjective'] = [
          for (final entry in historyFields.entries)
            if (fields[entry.key]!.text.trim().isNotEmpty)
              '${entry.value}: ${fields[entry.key]!.text.trim()}',
        ].join('\n');
        if ((raw['subjective'] as String).length > 4000) {
          // Structured sections retain their full content; SOAP is a short index.
          raw['subjective'] =
              'Historia clínica estructurada; consultar apartados.';
        }
      }
      if (widget.kind == EventKind.preventive) {
        raw['preventive_version'] = 1;
        raw['coverage_version'] = 1;
        raw['coverage_components'] = components.toList()..sort();
        raw['coverage_other'] = fields['coverage_other']!.text;
        raw['coverage'] = coverageText(
          components.toList()..sort(),
          fields['coverage_other']!.text,
        );
        raw['origin'] = origin;
        raw['date_precision'] = precision;
        if (precision != 'exact') {
          // The required legacy date is a record date, never an invented application date.
          raw['date'] = registrationDate;
        }
      }
      final payload = validateEvent(widget.kind, raw);
      if (widget.kind == EventKind.soap && !reviewed) {
        throw const FormatException('Revisa la nota antes de guardarla.');
      }
      // Preserve operation identifier for retry; edits get a fresh identifier.
      if (attempted != null && !_same(attempted!, payload)) {
        operationId = newOperationId();
      }
      attempted = payload;
      final problem = await widget.save(payload, operationId);
      if (!mounted) return;
      if (problem == null) {
        exit.close(context, true);
        return;
      }
      setState(() => error = problem);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool _same(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(a) == jsonEncode(b);
  Widget input(String key, String label, {int lines = 1, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          enabled: !busy && !listening,
          controller: fields[key],
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            helperText: hint,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {
            reviewed = false;
            if (widget.kind == EventKind.consent) {
              accepted = false;
              signature = [];
              signatureRevision++;
            }
          }),
        ),
      );
  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: dirty,
    busy: busy || listening,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.history ? 'Historia clínica' : widget.kind.label),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${widget.patient.name} · ${widget.patient.species}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (widget.kind != EventKind.preventive || precision == 'exact')
            input(
              'date',
              widget.kind == EventKind.preventive
                  ? 'Fecha de aplicación (AAAA-MM-DD)'
                  : 'Fecha clínica (AAAA-MM-DD)',
            ),
          ...switch (widget.kind) {
            EventKind.soap => [
              input('reason', 'Motivo de consulta'),
              if (widget.history) ...[
                const Text(
                  'Deja sin capturar lo desconocido. No equivale a ausencia de antecedentes. Vacunas, pesos y alergias se consultan en el expediente.',
                ),
                for (final entry in historyFields.entries)
                  input(entry.key, entry.value, lines: 3),
              ],
              for (final pair in <(String, String)>[
                ('subjective', 'S · Subjetivo'),
                ('objective', 'O · Objetivo'),
                ('assessment', 'A · Valoración'),
                ('plan', 'P · Plan'),
              ])
                if (!widget.history || pair.$1 != 'subjective')
                  input(
                    pair.$1,
                    pair.$2,
                    lines: 3,
                    hint: SoapTemplate.prompts(widget.patient.species)[pair.$1],
                  ),
              const Text(
                'El dictado usa el servicio de voz del dispositivo y puede requerir conexión. Revisa el texto reconocido antes de guardar; no genera diagnósticos.',
              ),
              DropdownButtonFormField<String>(
                initialValue: target,
                decoration: const InputDecoration(
                  labelText: 'Apartado para dictar',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'subjective',
                    child: Text('Subjetivo'),
                  ),
                  DropdownMenuItem(value: 'objective', child: Text('Objetivo')),
                  DropdownMenuItem(
                    value: 'assessment',
                    child: Text('Valoración'),
                  ),
                  DropdownMenuItem(value: 'plan', child: Text('Plan')),
                ],
                onChanged: busy || listening
                    ? null
                    : (v) => setState(() => target = v ?? target),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : toggleVoice,
                icon: Icon(listening ? Icons.stop : Icons.mic_none),
                label: Text(
                  listening ? 'Detener dictado' : 'Dictar en español',
                ),
              ),
              CheckboxListTile(
                title: const Text(
                  'Revisé el paciente y el contenido de esta nota.',
                ),
                value: reviewed,
                onChanged: busy || listening
                    ? null
                    : (v) => setState(() => reviewed = v ?? false),
              ),
            ],
            EventKind.weight => [input('kg', 'Peso (kg)')],
            EventKind.allergy => [
              input('substance', 'Sustancia / producto'),
              input('reaction', 'Reacción observada o referida', lines: 3),
              input('notes', 'Notas', lines: 2),
            ],
            EventKind.preventive => [
              DropdownButtonFormField<String>(
                initialValue: origin,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Origen del registro',
                ),
                items: [
                  for (final e in preventiveOrigins.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        origin = v;
                        fields['date']!.clear();
                        precision = 'exact';
                      }),
              ),
              if (origin != 'clinic') ...[
                DropdownButtonFormField<String>(
                  key: ValueKey(origin),
                  initialValue: precision,
                  decoration: const InputDecoration(
                    labelText: 'Fecha conocida',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'exact', child: Text('Exacta')),
                    DropdownMenuItem(
                      value: 'approximate',
                      child: Text('Aproximada'),
                    ),
                    DropdownMenuItem(
                      value: 'unknown',
                      child: Text('Desconocida'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => precision = v ?? 'unknown'),
                ),
              ],
              if (precision == 'approximate')
                input('date_description', 'Fecha aproximada referida'),
              if (precision != 'exact')
                const Text(
                  'La fecha de registro se conserva por separado; no se inventará una fecha de aplicación.',
                ),
              if (origin == 'clinic')
                input('performer', 'Persona que aplicó el producto'),
              if (origin == 'owner_report')
                input('informant', 'Persona que refiere el antecedente'),
              if (origin == 'external_document')
                input(
                  'evidence_reference',
                  'Referencia del carnet o comprobante revisado',
                  hint:
                      'Describe documento, fecha y emisor si se conocen. Después de guardar podrás adjuntar el comprobante desde el carnet; no acredita autenticidad.',
                ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'vacuna', child: Text('Vacuna')),
                  DropdownMenuItem(
                    value: 'desparasitación',
                    child: Text('Desparasitación'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() => type = v ?? type),
              ),
              const SizedBox(height: 16),
              const Text(
                'Selecciona solo lo que consta en la etiqueta, el carnet o el antecedente referido. Triple, séxtuple y otras combinaciones no tienen cobertura automática.',
              ),
              ExpansionTile(
                title: const Text('Coberturas / componentes conocidos'),
                children: [
                  for (final entry in preventiveCoverages.entries)
                    CheckboxListTile(
                      title: Text(entry.value),
                      value: components.contains(entry.key),
                      onChanged: busy
                          ? null
                          : (selected) => setState(() {
                              if (selected == true) {
                                components.add(entry.key);
                              } else {
                                components.remove(entry.key);
                              }
                            }),
                    ),
                ],
              ),
              input(
                'coverage_other',
                'Otra cobertura o detalles (si se conocen)',
                lines: 2,
                hint:
                    'Puedes conservar el nombre triple o séxtuple como referencia sin deducir componentes.',
              ),
              input('product', 'Producto / marca (si se conoce)'),
              input('batch', 'Lote (si está disponible)'),
              input(
                'next_date',
                'Próxima fecha (AAAA-MM-DD, opcional)',
                hint:
                    'La indica el MVZ. Sin fecha de aplicación conocida, debe ser igual o posterior al registro; no se asigna automáticamente.',
              ),
              input(
                'next_date_by',
                'Profesional que indicó la próxima fecha (si existe)',
              ),
              input('notes', 'Notas', lines: 2),
            ],
            EventKind.consent => [
              input('procedure', 'Procedimiento'),
              input(
                'text',
                'Texto del consentimiento aprobado por la clínica',
                lines: 8,
                hint:
                    'Pega el texto que corresponda al procedimiento; no hay plantillas legales precargadas.',
              ),
              input('signer', 'Nombre del tutor que firma'),
              CheckboxListTile(
                title: const Text('El tutor leyó y acepta el texto indicado.'),
                value: accepted,
                onChanged: busy
                    ? null
                    : (v) => setState(() => accepted = v ?? false),
              ),
              IgnorePointer(
                ignoring: busy,
                child: SignaturePad(
                  key: ValueKey(signatureRevision),
                  onChanged: (points) => setState(() => signature = points),
                ),
              ),
            ],
          },
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy || listening ? null : save,
            child: Text(busy ? 'Guardando…' : 'Guardar en el expediente'),
          ),
        ],
      ),
    ),
  );
}
