import '../../core/presentation/unsaved_form_scope.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../domain/patient_models.dart';
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
  });
  final EventKind kind;
  final VetPatient patient;
  final Future<String?> Function(Map<String, dynamic>, String) save;
  final VoiceDictation? voice;
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
      type != 'vacuna';
  final fields = <String, TextEditingController>{};
  late final VoiceDictation voice;
  String operationId = newOperationId();
  Map<String, dynamic>? attempted;
  List<List<double>?> signature = [];
  int signatureRevision = 0;
  bool accepted = false, busy = false, reviewed = false, listening = false;
  String type = 'vacuna', target = 'subjective';
  String? error;
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
    ]) {
      fields[k] = TextEditingController();
    }
    fields['date']!.text = DateTime.now().toIso8601String().substring(0, 10);
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
      appBar: AppBar(title: Text(widget.kind.label)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${widget.patient.name} · ${widget.patient.species}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          input('date', 'Fecha (AAAA-MM-DD)'),
          ...switch (widget.kind) {
            EventKind.soap => [
              input('reason', 'Motivo de consulta'),
              for (final pair in <(String, String)>[
                ('subjective', 'S · Subjetivo'),
                ('objective', 'O · Objetivo'),
                ('assessment', 'A · Valoración'),
                ('plan', 'P · Plan'),
              ])
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
              input('product', 'Producto aplicado'),
              input('batch', 'Lote (si está disponible)'),
              input(
                'next_date',
                'Próxima fecha (AAAA-MM-DD, opcional)',
                hint:
                    'La fecha la indica el MVZ; no se asigna automáticamente.',
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
