import '../../core/domain/plan_errors.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../forms/clinical/clinical_models.dart';
import '../../patients/presentation/signature_pad.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/prescribing_models.dart';

class RxField {
  const RxField(
    this.key,
    this.label, {
    this.type = 'text',
    this.options = const {},
    this.required = false,
  });
  final String key, label, type;
  final Map<String, String> options;
  final bool required;
}

class RxEntryScreen extends StatefulWidget {
  const RxEntryScreen({
    super.key,
    required this.title,
    required this.fields,
    required this.submit,
    this.initial = const {},
    this.products = const [],
  });
  final String title;
  final List<RxField> fields;
  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> products;
  final Future<void> Function(Map<String, dynamic>, String) submit;
  @override
  State<RxEntryScreen> createState() => _RxEntryScreenState();
}

class _RxEntryScreenState extends State<RxEntryScreen> {
  late final Map<String, dynamic> data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(widget.initial)),
  );
  late final String original = jsonEncode(widget.initial);
  bool leaving = false, askingToLeave = false;
  bool get dirty => jsonEncode(data) != original;
  Future<void> leave() async {
    if (busy || askingToLeave) return;
    if (dirty) {
      askingToLeave = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cambios sin guardar'),
          content: const Text(
            'Si sales, perderás los cambios de este formulario.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir editando'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salir sin guardar'),
            ),
          ],
        ),
      );
      askingToLeave = false;
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  bool busy = false;
  String? error;
  String operation = newOperationId(), previous = '';
  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      for (final f in widget.fields) {
        final v = data[f.key];
        if (f.required &&
            ((f.type == 'checkbox' && v != true) ||
                v == null ||
                (v is String && v.trim().isEmpty) ||
                (v is List && v.isEmpty))) {
          throw FormatException('Completa ${f.label}.');
        }
        if (f.type == 'quantity' && v != null && v != '') {
          data[f.key] = exactMedicationQuantity(v);
        }
        if ((f.type == 'instant' || f.type == 'local_instant') &&
            v != null &&
            v != '') {
          clinicalInstant(v);
        }
      }
      final payload = jsonEncode(data);
      if (previous.isNotEmpty && previous != payload) {
        operation = newOperationId();
      }
      previous = payload;
      await widget.submit(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map),
        operation,
      );
      if (mounted) {
        setState(() => leaving = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, true);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : rxError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(RxField f) {
    if (f.type == 'checkbox') {
      return CheckboxListTile(
        title: Text(f.label),
        value: data[f.key] == true,
        onChanged: busy
            ? null
            : (v) => setState(() => data[f.key] = v ?? false),
      );
    }
    if (f.type == 'select') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          initialValue: f.options.containsKey(data[f.key]) ? data[f.key] : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '${f.label}${f.required ? ' *' : ''}',
          ),
          items: [
            for (final e in f.options.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(
                  e.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy ? null : (v) => setState(() => data[f.key] = v),
        ),
      );
    }
    if (f.type == 'local_instant') {
      final instant = DateTime.tryParse('${data[f.key] ?? ''}')?.toLocal();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ListTile(
          title: Text('${f.label}${f.required ? ' *' : ''}'),
          subtitle: Text(
            instant == null
                ? 'Selecciona fecha y hora local'
                : '${instant.day.toString().padLeft(2, '0')}/${instant.month.toString().padLeft(2, '0')}/${instant.year} · ${instant.hour.toString().padLeft(2, '0')}:${instant.minute.toString().padLeft(2, '0')}',
          ),
          trailing: const Icon(Icons.calendar_month),
          onTap: busy
              ? null
              : () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: instant ?? now,
                    firstDate: DateTime(1970),
                    lastDate: DateTime(now.year + 10, 12, 31),
                  );
                  if (date == null || !mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(instant ?? now),
                  );
                  if (time == null || !mounted) return;
                  setState(
                    () => data[f.key] = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    ).toUtc().toIso8601String(),
                  );
                },
        ),
      );
    }
    if (f.type == 'signature') {
      return SignaturePad(
        label: f.label,
        onChanged: (points) {
          if (!busy) setState(() => data[f.key] = points);
        },
      );
    }
    if (f.type == 'items') return items(f);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: data[f.key]?.toString() ?? '',
        enabled: !busy,
        maxLines: f.type == 'text' ? null : 1,
        maxLength: f.key.contains('reason') ? 1000 : 4000,
        decoration: InputDecoration(
          labelText: '${f.label}${f.required ? ' *' : ''}',
          helperText: f.type == 'instant'
              ? 'AAAA-MM-DDTHH:MM:SSZ (UTC)'
              : f.type == 'quantity'
              ? 'Cantidad real exacta; no una dosis sugerida'
              : null,
        ),
        onChanged: (v) => setState(() => data[f.key] = v),
      ),
    );
  }

  Widget items(RxField f) {
    final rows = (data[f.key] as List? ?? []).cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(f.label),
        const Text(
          'Captura las indicaciones revisadas por el responsable. No se proponen dosis ni intervalos.',
        ),
        for (var i = 0; i < rows.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('product-${identityHashCode(rows[i])}'),
                    initialValue:
                        widget.products.any(
                          (p) => p['id'] == rows[i]['product_version_id'],
                        )
                        ? rows[i]['product_version_id']
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Producto y presentación',
                    ),
                    items: [
                      for (final p in widget.products)
                        DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                            '${p['name']} · ${p['presentation']} · ${p['source_status']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (id) => setState(() {
                            rows[i]['product_version_id'] = id;
                            rows[i]['unit'] = widget.products.firstWhere(
                              (p) => p['id'] == id,
                            )['unit'];
                          }),
                  ),
                  for (final e in {
                    'quantity':
                        'Cantidad por administración (${rows[i]['unit'] ?? 'unidad pendiente'})',
                    'route': 'Vía',
                    'interval': 'Intervalo',
                    'duration': 'Duración',
                    'care': 'Cuidados / indicaciones',
                  }.entries)
                    TextFormField(
                      key: ValueKey('${identityHashCode(rows[i])}-${e.key}'),
                      initialValue: rows[i][e.key],
                      enabled: !busy,
                      maxLength: e.key == 'care' ? 4000 : 1000,
                      decoration: InputDecoration(labelText: e.value),
                      onChanged: (v) => setState(() => rows[i][e.key] = v),
                    ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            rows.removeAt(i);
                            data[f.key] = rows;
                          }),
                    child: const Text('Quitar indicación'),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton(
          onPressed: busy || rows.length >= 40 || widget.products.isEmpty
              ? null
              : () => setState(
                  () => data[f.key] = [...rows, <String, dynamic>{}],
                ),
          child: const Text('Añadir producto'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: leaving || (!busy && !dirty),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: BackButton(onPressed: busy ? null : leave),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final f in widget.fields) field(f),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
    ),
  );
}

String rxError(Object error) {
  final planMessage = planActionError(error);
  if (planMessage != null) return planMessage;
  final text = error.toString();
  for (final e in {
    'task_version_conflict':
        'La indicación cambió. Actualiza la hoja y revisa antes de confirmar.',
    'task_closed_without_application':
        'La dosis quedó sin aplicación o cancelada por alta. No se registró una toma.',
    'hospital_task_version_required':
        'Actualiza la tarea antes de confirmar la aplicación.',
    'task_already_confirmed':
        'La tarea ya fue confirmada. Actualiza la hoja; no se registró otra toma.',
    'explicit_permission_required':
        'Falta un permiso vigente para esta acción. Actualiza o consulta con la administración.',
    'permission_not_valid_at_application':
        'El permiso no estaba vigente en la hora indicada. Revisa el registro con el responsable.',
    'controlled_or_unverified_vial_adjustment_denied':
        'Este frasco no admite ajustes libres: es controlado o su clasificación está sin verificar.',
    'legacy_medication_reauthorization_required':
        'El registro histórico requiere revisión antes de usar el nuevo flujo de autorización.',
    'profile_version_conflict': 'El perfil cambió. Actualiza antes de guardar.',
    'delegated_restricted_product_denied':
        'El producto es restringido o su clasificación no está verificada. Un auxiliar no puede preparar esa receta.',
    'controlled_responsible_only':
        'Solo el MVZ responsable puede preparar o emitir controlados.',
    'responsible_professional_only':
        'Esta acción requiere al MVZ responsable habilitado.',
    'verified_controlled_format_and_captured_folio_required':
        'Falta un formato controlado verificado o el folio capturado por el MVZ.',
    'verified_official_report_format_required':
        'No hay un formato oficial verificado. Puedes preparar un reporte de referencia.',
    'verified_current_product_required':
        'La clasificación del producto no está verificada o cambió. Actualiza la receta.',
    'delegation_revoked_or_expired':
        'El permiso fue revocado o venció. No se emitió el documento.',
    'discrepancy_mvZ_note_required':
        'Hay discrepancia. El cierre requiere una nota del MVZ y conserva la diferencia.',
    'unresolved_incidence_requires_correction':
        'La aplicación tiene una incidencia. Debe corregirse y revisarse antes de validarla.',
  }.entries) {
    if (text.contains(e.key)) return e.value;
  }
  return 'No se guardó. Revisa permisos vigentes, campos, cantidades y conexión; actualiza antes de reintentar.';
}
