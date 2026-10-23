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
    this.reviewText,
    this.submitLabel = 'Guardar',
  });
  final String title;
  final List<RxField> fields;
  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> products;
  final String? reviewText;
  final String submitLabel;
  final Future<void> Function(Map<String, dynamic>, String) submit;
  @override
  State<RxEntryScreen> createState() => _RxEntryScreenState();
}

class _RxEntryScreenState extends State<RxEntryScreen> {
  final Map<String, String> optionQueries = {};
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
        if (f.required && f.type == 'checkbox' && v != true) {
          throw FormatException('Confirma ${f.label}.');
        }
        if (f.type == 'local_date' && v != null && v != '') {
          final text = '$v', parsed = DateTime.tryParse('$v');
          if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
              parsed == null ||
              parsed.toIso8601String().substring(0, 10) != text) {
            throw FormatException(
              'Selecciona una fecha válida para ${f.label}.',
            );
          }
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
    if (f.type == 'multi_select') {
      final selected = (data[f.key] as List? ?? []).cast<String>();
      final query = optionQueries[f.key]?.toLowerCase() ?? '';
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          decoration: InputDecoration(labelText: f.label, prefixIcon: const Icon(Icons.search)),
          onChanged: (value) => setState(() => optionQueries[f.key] = value),
        ),
        for (final option in f.options.entries.where((e) => e.value.toLowerCase().contains(query)))
          CheckboxListTile(
            title: Text(option.value),
            value: selected.contains(option.key),
            onChanged: busy ? null : (checked) => setState(() {
              final next = [...selected];
              if (checked == true && !next.contains(option.key)) next.add(option.key);
              if (checked == false) next.remove(option.key);
              data[f.key] = next;
            }),
          ),
      ]);
    }
    if (f.type == 'search_select') {
      return Autocomplete<String>(
        initialValue: TextEditingValue(text: f.options[data[f.key]] ?? ''),
        optionsBuilder: (value) => value.text.trim().isEmpty
            ? f.options.keys
            : f.options.entries.where((e) => e.value.toLowerCase().contains(value.text.toLowerCase())).map((e) => e.key),
        displayStringForOption: (id) => f.options[id] ?? id,
        onSelected: (id) => setState(() => data[f.key] = id),
        fieldViewBuilder: (context, controller, focus, submit) => TextField(
          controller: controller,
          focusNode: focus,
          enabled: !busy,
          decoration: InputDecoration(labelText: f.label, prefixIcon: const Icon(Icons.search)),
          onChanged: (_) => data.remove(f.key),
        ),
      );
    }
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
    if (f.type == 'local_date') {
      final selected = DateTime.tryParse('${data[f.key] ?? ''}');
      return ListTile(
        title: Text('${f.label}${f.required ? ' *' : ''}'),
        subtitle: Text(
          selected == null
              ? 'Selecciona fecha'
              : '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}',
        ),
        trailing: const Icon(Icons.calendar_month),
        onTap: busy
            ? null
            : () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selected ?? DateTime.now(),
                  firstDate: DateTime(1970),
                  lastDate: DateTime(DateTime.now().year + 10, 12, 31),
                );
                if (date != null && mounted) {
                  setState(
                    () => data[f.key] =
                        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                  );
                }
              },
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
                    'invalid_clinical_date':
                        'Selecciona una fecha clínica válida que no sea futura.',
                    'explicit_clinical_date_required':
                        'Selecciona explícitamente la fecha clínica.',
                    'explicit_verified_case_responsible_required':
                        'Selecciona un MVZ habilitado con permiso vigente para este espacio.',
                    'invalid_case_context':
                        'Revisa el contexto, el motivo (hasta 300 caracteres) y las notas (hasta 4000).',
                    'case_context_fields_only':
                        'El caso inicial solo guarda contexto. Registra mediciones y actuaciones en sus apartados.',
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
          if (widget.reviewText != null) SelectableText(widget.reviewText!),
          for (final f in widget.fields) field(f),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Guardando…' : widget.submitLabel),
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
    'standing_authorization_unavailable':
        'La autorización temporal venció, fue revocada o cambiaron sus permisos. Actualiza; el documento no se emitió.',
    'standing_expiry_outside_permissions':
        'Elige un vencimiento futuro dentro de la vigencia de tus permisos y los de la persona a cargo.',
    'standing_acceptance_required':
        'La persona a cargo debe aceptar explícitamente la autorización.',
    'standing_recipient_only':
        'Esta acción corresponde únicamente a la persona destinataria de la autorización.',
    'responsible_explicit_authorization_required':
        'El MVZ responsable de este caso debe confirmar la autorización previa.',
    'recipient_preparation_permissions_required':
        'La persona necesita permisos vigentes para consultar el caso y preparar recetas.',
    'responsible_review_only':
        'Solo el MVZ que otorgó esta autorización puede registrar su revisión posterior.',
    'reviewed_prescription_mismatch':
        'El PDF o la versión no coincide con la receta seleccionada. Actualiza y vuelve a revisarlo.',
    'post_review_confirmation_required':
        'Confirma que revisaste la receta emitida y su PDF.',
    'post_review_already_recorded':
        'Esta revisión ya quedó registrada y no se sobrescribe.',
    'invalid_signature': 'Dibuja tu firma en el recuadro antes de continuar.',
    'prescription_revision_conflict':
        'La receta cambió. Actualiza y revisa la versión vigente antes de continuar.',
    'consultation_signature_stale':
        'El contenido cambió después de firmar. Quien realizó la consulta debe firmar la nueva versión.',
    'consultation_signature_required':
        'Falta la firma de quien realizó la consulta sobre este borrador.',
    'consultation_signer_authority_changed':
        'Cambió el acceso de quien firmó. Actualiza y solicita revisión del responsable.',
    'preparer_authority_changed':
        'El acceso de quien preparó dejó de estar vigente. El documento no se emitió.',
    'responsible_profile_changed':
        'Los datos o la habilitación del responsable cambiaron. Devuelve a borrador para revisar.',
    'prescription_authorization_changed':
        'La autorización dejó de estar vigente. El documento no se emitió.',
    'prescription_regulation_changed':
        'Cambió la referencia del formato controlado. Devuelve a borrador para revisar antes de emitir.',
    'individual_authorization_required':
        'El MVZ responsable debe autorizar las indicaciones antes de generar el PDF.',
    'individual_responsible_only':
        'Solo el MVZ responsable habilitado y con permiso puede autorizar o emitir esta receta.',
    'consultation_profile_name_mismatch':
        'El nombre de quien realizó la consulta debe coincidir con sus datos profesionales.',
    'preparer_profile_name_mismatch':
        'Tu nombre debe coincidir con tus datos profesionales vigentes.',
    'typed_standing_authorization_not_available':
        'La autorización permanente todavía no está habilitada en este flujo.',
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
        'La preparación por otra persona requiere un producto ordinario con clasificación verificada. Consulta con el MVZ responsable.',
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
    'signature_required': 'Falta una firma válida en el recuadro.',
  }.entries) {
    if (text.contains(e.key)) return e.value;
  }
  return 'No se guardó. Revisa permisos vigentes, campos, cantidades y conexión; actualiza antes de reintentar.';
}
