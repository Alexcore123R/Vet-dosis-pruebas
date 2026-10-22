import '../../core/presentation/unsaved_form_scope.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/form_models.dart';
import '../domain/form_repository.dart';
import 'form_pdf_screen.dart';

class TemplateEditor extends StatefulWidget {
  const TemplateEditor({
    super.key,
    required this.repository,
    required this.clinicId,
    required this.original,
    this.restore,
    this.canApprove = true,
  });
  final bool canApprove;
  final FormRepository repository;
  final String clinicId;
  final FormTemplateVersion original;
  final Map<String, dynamic>? restore;
  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  final exit = FormExitController();
  bool get dirty =>
      fingerprint != jsonEncode(widget.original.schema) ||
      reason.text.isNotEmpty ||
      approved;
  late Map<String, dynamic> schema;
  final reason = TextEditingController();
  bool approved = false, busy = false;
  String? error, previewFingerprint, operationFingerprint;
  String operation = newOperationId();
  String get fingerprint => jsonEncode(schema);
  void changed() {
    setState(() {
      previewFingerprint = null;
      approved = false;
    });
  }

  @override
  void initState() {
    super.initState();
    reason.addListener(() {
      if (mounted) setState(() {});
    });
    schema = jsonDecode(jsonEncode(widget.restore ?? widget.original.schema));
  }

  @override
  void dispose() {
    exit.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> preview() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final expected = fingerprint;
      final pdf = await widget.repository.templatePreview(
        widget.clinicId,
        validateTemplate(schema),
        await widget.repository.branding(widget.clinicId),
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              FormPdfScreen(pdf: pdf, title: 'Vista previa de plantilla'),
        ),
      );
      if (mounted && fingerprint == expected) {
        setState(() => previewFingerprint = expected);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se pudo generar la vista previa.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (previewFingerprint != fingerprint || reason.text.trim().isEmpty) {
        throw const FormatException('Revisa el PDF y escribe un motivo.');
      }
      if (approved && !widget.canApprove) {
        throw StateError('template_approval_required');
      }
      final current = '$fingerprint:$approved:${reason.text.trim()}';
      if (operationFingerprint != null && operationFingerprint != current) {
        operation = newOperationId();
      }
      operationFingerprint = current;
      await widget.repository.saveTemplate(
        widget.clinicId,
        widget.original.clinicId == null ? null : widget.original.templateId,
        widget.original.clinicId == null ? null : widget.original.version,
        widget.original.clinicId == null
            ? widget.original.id
            : widget.original.baseVersionId,
        validateTemplate(schema),
        approved,
        reason.text.trim(),
        operation,
      );
      if (mounted) exit.close(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se guardó. Actualiza las versiones antes de reintentar si hubo un conflicto.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addField() async {
    final label = TextEditingController();
    final choices = TextEditingController();
    String type = 'text';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Nueva pregunta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Pregunta'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Texto')),
                    DropdownMenuItem(value: 'date', child: Text('Fecha')),
                    DropdownMenuItem(value: 'number', child: Text('Número')),
                    DropdownMenuItem(value: 'checkbox', child: Text('Casilla')),
                    DropdownMenuItem(
                      value: 'single',
                      child: Text('Selección única'),
                    ),
                    DropdownMenuItem(
                      value: 'multiple',
                      child: Text('Selección múltiple'),
                    ),
                    DropdownMenuItem(
                      value: 'table',
                      child: Text('Tabla repetible'),
                    ),
                  ],
                  onChanged: (v) => update(() => type = v!),
                ),
                if (['single', 'multiple', 'table'].contains(type))
                  TextField(
                    controller: choices,
                    decoration: InputDecoration(
                      labelText: type == 'table'
                          ? 'Columnas separadas por coma'
                          : 'Opciones separadas por coma',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (label.text.trim().isEmpty) return;
                final options = choices.text
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toSet()
                    .toList();
                if (['single', 'multiple', 'table'].contains(type) &&
                    options.isEmpty) {
                  return;
                }
                Navigator.pop(context, {
                  'id': 'extra_${DateTime.now().microsecondsSinceEpoch}',
                  'label': label.text.trim(),
                  'type': type,
                  'required': false,
                  'locked': false,
                  if (type == 'single' || type == 'multiple')
                    'options': options,
                  if (type == 'table') 'columns': options,
                });
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    choices.dispose();
    if (result != null && mounted) {
      (schema['fields'] as List).add(result);
      changed();
    }
  }

  void addClause() {
    (schema['clauses'] as List).add({
      'id': 'clause_${DateTime.now().microsecondsSinceEpoch}',
      'text': '',
      'locked': false,
    });
    changed();
  }

  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: dirty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Plantilla de la clínica')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Plantilla de referencia. La clínica es responsable de revisar y aprobar el contenido final. Guardar crea una versión nueva.',
            ),
            TextFormField(
              initialValue: schema['title'],
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (v) {
                schema['title'] = v;
                changed();
              },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                'Campos del documento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const Text(
              'Define qué datos variables se capturan al llenar el formato. Los datos protegidos del paciente, tutor y profesional no se pueden eliminar.',
            ),
            for (final f in (schema['fields'] as List).cast<Map>())
              ListTile(
                leading: Icon(
                  f['locked'] == true
                      ? Icons.lock_outline
                      : Icons.edit_outlined,
                ),
                title: Text(f['label']),
                subtitle: Text(
                  '${f['type']} · ${f['required'] == true ? 'obligatorio' : 'opcional'}',
                ),
                trailing: f['locked'] == true
                    ? null
                    : IconButton(
                        tooltip: 'Eliminar pregunta',
                        onPressed: busy
                            ? null
                            : () {
                                (schema['fields'] as List).remove(f);
                                changed();
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
              ),
            OutlinedButton(
              onPressed: busy ? null : addField,
              child: const Text('Agregar pregunta o tabla'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                'Cláusulas e indicaciones fijas',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const Text(
              'Este texto se incorpora al documento para que el tutor lo lea y lo acepte. No se modifica al llenar un consentimiento.',
            ),
            for (final c in (schema['clauses'] as List).cast<Map>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextFormField(
                  initialValue: c['text'],
                  readOnly: c['locked'] == true,
                  maxLines: null,
                  maxLength: 12000,
                  decoration: InputDecoration(
                    labelText: c['id'] == 'revocation'
                        ? 'Revocación (protegida)'
                        : 'Información / cláusula de la clínica',
                  ),
                  onChanged: (v) {
                    c['text'] = v;
                    changed();
                  },
                ),
              ),
            OutlinedButton(
              onPressed: busy ? null : addClause,
              child: const Text('Agregar cláusula propia'),
            ),
            TextField(
              controller: reason,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Motivo de la nueva versión',
              ),
            ),
            CheckboxListTile(
              value: approved,
              onChanged: busy || !widget.canApprove
                  ? null
                  : (v) => setState(() => approved = v ?? false),
              title: const Text(
                'La clínica revisó y aprobó esta versión para usarla. Esto no certifica su validez legal.',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            OutlinedButton(
              onPressed: busy ? null : preview,
              child: const Text('Vista previa PDF antes de guardar'),
            ),
            FilledButton(
              onPressed: busy || previewFingerprint != fingerprint
                  ? null
                  : save,
              child: const Text('Guardar versión nueva'),
            ),
          ],
        ),
      ),
    ),
  );
}
