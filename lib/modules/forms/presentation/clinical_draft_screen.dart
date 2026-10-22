import 'dart:convert';
import 'package:flutter/material.dart';
import '../../ai/domain/ai_repository.dart';
import '../../ai/domain/assisted_drafts.dart';
import '../../ai/presentation/request_ai_draft.dart';
import '../../ai/presentation/dictation_field.dart';
import '../../auth/domain/clinic_membership.dart';

class ClinicalDraftScreen extends StatefulWidget {
  const ClinicalDraftScreen({
    super.key,
    required this.ai,
    required this.member,
    required this.fields,
    required this.currentValues,
    required this.documentTitle,
  });
  final AiRepository ai;
  final ClinicMembership member;
  final Map<String, String> fields;
  final Map<String, dynamic> currentValues;
  final String documentTitle;
  @override
  State<ClinicalDraftScreen> createState() => _ClinicalDraftScreenState();
}

class _ClinicalDraftScreenState extends State<ClinicalDraftScreen> {
  final notes = TextEditingController();
  final selected = <String>{};
  final output = <String, TextEditingController>{};
  List<String> missing = [];
  String mode = 'indicaciones';
  bool listening = false, reviewed = false;
  String? error;
  String? generatedInput;
  String get inputFingerprint => jsonEncode({
    'mode': mode,
    'selected': selected.toList()..sort(),
    'notes': notes.text,
  });
  bool get draftMatches => generatedInput == inputFingerprint;
  @override
  void initState() {
    super.initState();
    selected.addAll(
      widget.fields.keys.where(
        (id) => [
          'plan',
          'notes',
          'instructions',
          'indications',
          'recommendations',
          'discharge',
        ].contains(id),
      ),
    );
    if (selected.isEmpty && widget.fields.isNotEmpty) {
      selected.add(widget.fields.keys.first);
    }
  }

  @override
  void dispose() {
    notes.dispose();
    for (final c in output.values) {
      c.dispose();
    }
    super.dispose();
  }

  void invalidate() {
    setState(() => reviewed = false);
  }

  Future<void> prepare() async {
    if (selected.isEmpty) {
      setState(() => error = 'Selecciona los campos que deseas preparar.');
      return;
    }
    final contextValues = {
      for (final id in selected)
        if ('${widget.currentValues[id] ?? ''}'.isNotEmpty)
          id: '${widget.currentValues[id]}',
    };
    if (notes.text.trim().isEmpty && contextValues.isEmpty) {
      setState(
        () => error =
            'Escribe o dicta las indicaciones y hechos del profesional antes de redactar.',
      );
      return;
    }
    if (jsonEncode(contextValues).length + notes.text.length > 14000) {
      setState(
        () => error =
            'Selecciona menos campos o reduce las notas para preparar el borrador sin recortar información.',
      );
      return;
    }
    final sourceFingerprint = inputFingerprint;
    final raw = await requestAiDraft(
      context,
      repository: widget.ai,
      member: widget.member,
      title: 'Borrador clínico: $mode',
      prompt:
          'Prepara un borrador de ${mode == 'alta'
              ? 'alta médica'
              : mode == 'indicaciones'
              ? 'indicaciones para el tutor'
              : 'notas clínicas ordenadas'} para el formato "${widget.documentTitle}". '
          'Solo puedes redactar estos campos seleccionados: ${jsonEncode({for (final id in selected) id: widget.fields[id]})}. '
          'Contenido actual de esos campos: ${jsonEncode(contextValues)}. Notas escritas o dictadas por el profesional: ${notes.text.trim()}. '
          'No agregues diagnósticos, tratamientos, dosis, aptitud para el alta, resultados, autorizaciones ni cláusulas legales que el profesional no haya indicado. '
          'Conserva las indicaciones existentes y marca información faltante en missing. Para el alta, no afirmes que el paciente está dado de alta si eso no se indicó. '
          'No modifiques identidad, firmas ni campos no seleccionados. Devuelve solo JSON válido: {"fields":{"id_seleccionado":"texto redactado"},"missing":["dato pendiente"]}. '
          'Usa las claves reales seleccionadas, texto máximo 4000 caracteres por campo. La versión final será verificada y firmada por el profesional.',
    );
    if (!mounted || raw == null) return;
    try {
      final draft = ClinicalDraft.parse(raw, selected);
      for (final c in output.values) {
        c.dispose();
      }
      output.clear();
      setState(() {
        for (final item in draft.fields.entries) {
          output[item.key] = TextEditingController(text: item.value);
        }
        missing = draft.missing;
        generatedInput = sourceFingerprint;
        reviewed = false;
        error = null;
      });
    } catch (_) {
      setState(
        () => error =
            'La respuesta no contiene campos válidos del formato. Pide otra versión; no se modificó el documento.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preparar notas, indicaciones o alta')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Formato: ${widget.documentTitle}'),
        DropdownButtonFormField<String>(
          initialValue: mode,
          items: const [
            DropdownMenuItem(
              value: 'notas',
              child: Text('Ordenar notas clínicas'),
            ),
            DropdownMenuItem(
              value: 'indicaciones',
              child: Text('Redactar indicaciones'),
            ),
            DropdownMenuItem(
              value: 'alta',
              child: Text('Preparar borrador de alta médica'),
            ),
          ],
          onChanged: listening
              ? null
              : (v) => setState(() {
                  mode = v!;
                  reviewed = false;
                }),
        ),
        const Text(
          'Campos a preparar. Solo se enviará a la IA el contenido de los campos seleccionados y las notas de abajo.',
        ),
        for (final field in widget.fields.entries)
          CheckboxListTile(
            title: Text(field.value),
            value: selected.contains(field.key),
            onChanged: listening
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      selected.add(field.key);
                    } else {
                      selected.remove(field.key);
                    }
                    reviewed = false;
                  }),
          ),
        DictationField(
          controller: notes,
          label: 'Hechos e indicaciones del profesional',
          onChanged: invalidate,
          onListening: (v) => setState(() => listening = v),
        ),
        FilledButton.icon(
          onPressed: listening ? null : prepare,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Preparar borrador con IA'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final item in missing)
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text('Por completar: $item'),
          ),
        for (final field in output.entries)
          TextField(
            controller: field.value,
            maxLines: null,
            maxLength: 4000,
            decoration: InputDecoration(labelText: widget.fields[field.key]),
            onChanged: (_) => setState(() => reviewed = false),
          ),
        if (output.isNotEmpty) ...[
          if (!draftMatches)
            const Text(
              'Cambió el contexto o la selección de campos. Genera otro borrador antes de incorporarlo.',
            ),
          CheckboxListTile(
            title: const Text(
              'Revisé y corregí el borrador; está listo para incorporarse al formato y continuar su revisión profesional',
            ),
            value: reviewed,
            onChanged: listening || !draftMatches
                ? null
                : (v) => setState(() => reviewed = v == true),
          ),
          FilledButton(
            onPressed: !reviewed || listening || !draftMatches
                ? null
                : () => Navigator.pop(context, <String, String>{
                    for (final item in output.entries)
                      item.key: item.value.text.trim(),
                  }),
            child: const Text('Incorporar al documento'),
          ),
          const Text(
            'Después podrás guardar el borrador y continuar con la revisión del PDF y las firmas. Incorporar el texto no firma ni autoriza el documento.',
          ),
        ],
      ],
    ),
  );
}
