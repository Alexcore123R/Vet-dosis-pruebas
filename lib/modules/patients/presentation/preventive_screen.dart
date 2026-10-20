import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/domain/staff_labels.dart';
import '../../operations/presentation/operations_view_model.dart'
    show validateAppointmentTimes;
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../application/preventive_model.dart';
import '../application/preventive_pdf.dart';
import '../domain/preventive_repository.dart';
import '../domain/patient_models.dart';
import '../domain/patient_timeline.dart';
import '../domain/clinical_record_fields.dart';
import 'preventive_preview.dart';

class PreventiveScreen extends StatefulWidget {
  const PreventiveScreen({
    super.key,
    required this.repository,
    required this.clinic,
    required this.patient,
    required this.clinicName,
  });
  final PreventiveRepository repository;
  final String clinic, patient, clinicName;
  @override
  State<PreventiveScreen> createState() => _PreventiveScreenState();
}

class _PreventiveScreenState extends State<PreventiveScreen>
    with WidgetsBindingObserver {
  late final model = PreventiveModel(
    widget.repository,
    widget.clinic,
    widget.patient,
  );
  bool foreground = true;
  bool get current =>
      mounted && foreground && model.data != null && !model.busy;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      model.load();
    } else {
      model.clear();
    }
  }

  Future<void> form(
    String title,
    List<RxField> fields,
    Future<void> Function(Map<String, dynamic>, String) submit, {
    Map<String, dynamic> initial = const {},
    String? review,
  }) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: title,
          fields: fields,
          initial: initial,
          reviewText: review,
          submit: (d, op) async {
            if (!current) {
              throw const FormatException(
                'Actualiza el carnet antes de guardar.',
              );
            }
            try {
              await submit(d, op);
            } catch (e) {
              if (e is FormatException) rethrow;
              throw FormatException(bookletError(e));
            }
          },
        ),
      ),
    );
    if (mounted && saved == true) await model.load();
  }

  Future<void> attach(PatientEvent event) async {
    try {
      final source = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Agregar comprobante al carnet'),
                subtitle: Text('Foto, imagen guardada o PDF escaneado.'),
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Fotografiar documento'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Elegir foto'),
                onTap: () => Navigator.pop(context, 'photo'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Elegir PDF o escaneo'),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || source == null) return;
      final file = source == 'camera'
          ? await ImagePicker().pickImage(
              source: ImageSource.camera,
              imageQuality: 88,
              maxWidth: 2000,
              maxHeight: 2000,
            )
          : source == 'photo'
          ? await ImagePicker().pickImage(source: ImageSource.gallery)
          : (await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: ['pdf'],
            ))?.xFile;
      if (!mounted || file == null) return;
      if (await file.length() > maxPreventiveEvidence) {
        throw const FormatException('Selecciona un comprobante de hasta 3 MB.');
      }
      final bytes = await file.readAsBytes();
      final mime = evidenceMime(bytes);
      await model.load();
      if (!current ||
          model.data!['can_attach'] != true ||
          !model.rows('events').any((e) => e['id'] == event.id)) {
        return;
      }
      await form(
        'Adjuntar comprobante',
        const [RxField('label', 'Descripción del comprobante', required: true)],
        (d, op) => widget.repository.attachEvidence(
          widget.clinic,
          widget.patient,
          event.id,
          textField(d, 'label', required: true, max: 150),
          bytes,
          mime,
          op,
        ),
        initial: {'label': 'Comprobante de carnet'},
        review:
            'Archivo ${mime == 'application/pdf' ? 'PDF' : 'de imagen'} · ${(bytes.length / 1024).ceil()} KB. Adjuntarlo no modifica el origen del registro ni verifica su autenticidad.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'No se pudo seleccionar el comprobante.',
            ),
          ),
        );
      }
    }
  }

  Future<void> plan([PatientEvent? event]) async {
    await form(
      'Próxima aplicación · confirmación veterinaria',
      const [
        RxField(
          'type',
          'Tipo',
          type: 'select',
          required: true,
          options: {'vacuna': 'Vacuna', 'desparasitación': 'Desparasitación'},
        ),
        RxField('coverage', 'Cobertura o finalidad indicada', required: true),
        RxField('due_date', 'Fecha indicada (AAAA-MM-DD)', required: true),
        RxField(
          'reason',
          'Criterio o referencia de la indicación',
          required: true,
        ),
      ],
      (d, op) async {
        calendarDate(textField(d, 'due_date', required: true));
        await widget.repository.planPreventive(
          widget.clinic,
          widget.patient,
          d,
          op,
        );
      },
      initial: {
        if (event != null) 'event_id': event.id,
        if (event != null) 'type': event.data['type'],
        if (event != null)
          'coverage': event.data['coverage'] ?? event.data['product'] ?? '',
        if (event?.data['next_date'] != null)
          'due_date': event!.data['next_date'],
      },
      review:
          'Confirma la indicación como veterinario autorizado. No se deduce un esquema por edad, marca, triple o séxtuple; tampoco se crea una cita al guardar.',
    );
  }

  Future<void> schedule(Map<String, dynamic> plan) => form(
    'Agendar próxima aplicación',
    [
      RxField(
        'professional_id',
        'Integrante asignado',
        type: 'select',
        required: true,
        options: {
          for (final member in model.rows('members'))
            member['user_id'] as String: staffLabel(
              member['user_id'] as String,
              model.rows('members'),
            ),
        },
      ),
      const RxField(
        'starts_at',
        'Inicio de cita',
        type: 'local_instant',
        required: true,
      ),
      const RxField(
        'ends_at',
        'Fin de cita',
        type: 'local_instant',
        required: true,
      ),
    ],
    (d, op) async {
      validateAppointmentTimes(d);
      await widget.repository.schedulePreventive(
        widget.clinic,
        widget.patient,
        plan['id'] as String,
        d,
        op,
      );
    },
    review:
        'Fecha indicada: ${plan['due_date']}. Elige el horario de común acuerdo con el tutor. Si eliges otro día, la indicación original permanece sin cambios. La cita no acredita aplicación.',
  );
  Future<void> share() async {
    final repo = widget.repository,
        clinic = widget.clinic,
        patient = widget.patient,
        name = widget.clinicName;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreventivePreview(
          shareable: true,
          load: () async =>
              preventivePdf(await repo.booklet(clinic, patient), name),
        ),
      ),
    );
    if (mounted) await model.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Carnet preventivo'),
      actions: [
        IconButton(
          onPressed: model.load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualizar carnet',
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        if (model.busy) return const Center(child: CircularProgressIndicator());
        if (model.data == null) {
          return Center(child: Text(model.error ?? 'Carnet no disponible.'));
        }
        final events = patientTimeline(
          model.rows('events').map(PatientEvent.read).toList(),
          kind: EventKind.preventive,
        );
        final retired = (model.data!['retired'] as List).toSet();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${model.data!['patient_name']} · ${model.data!['species']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Aplicaciones y antecedentes conservan su origen. Un comprobante adjunto no verifica automáticamente el registro ni acredita un esquema completo.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: share,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Revisar / compartir carnet'),
                ),
                if (model.data!['can_confirm'] == true)
                  OutlinedButton(
                    onPressed: () => plan(),
                    child: const Text('Indicar próxima aplicación'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Próximas fechas confirmadas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Solo se confirman con autoridad veterinaria vigente. Retirar una indicación no cancela una cita en Agenda ni registra una aplicación.',
            ),
            if (!model.rows('plans').any((p) => !retired.contains(p['id'])))
              const Text('Sin próximas fechas confirmadas en este apartado.'),
            for (final p
                in model.rows('plans').where((p) => !retired.contains(p['id'])))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['due_date']} · ${p['type']} · ${p['coverage']}',
                      ),
                      const Text(
                        'Confirmada por veterinario autorizado. No equivale a aplicación.',
                      ),
                      for (final link
                          in model
                              .rows('links')
                              .where((l) => l['plan_id'] == p['id']))
                        Text(
                          'Cita vinculada: ${appointmentLabel(link['state'])}. Consulta el horario vigente en Agenda.',
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (model.data!['can_schedule'] == true &&
                              !model
                                  .rows('links')
                                  .any(
                                    (l) =>
                                        l['plan_id'] == p['id'] &&
                                        l['state'] != 'cancelado',
                                  ))
                            TextButton(
                              onPressed: () => schedule(p),
                              child: const Text('Agendar cita'),
                            ),
                          if (model.data!['can_confirm'] == true)
                            TextButton(
                              onPressed: () => form(
                                'Retirar indicación',
                                const [
                                  RxField(
                                    'reason',
                                    'Motivo de retiro o corrección',
                                    required: true,
                                  ),
                                ],
                                (d, op) => widget.repository.retirePlan(
                                  widget.clinic,
                                  widget.patient,
                                  p['id'] as String,
                                  textField(
                                    d,
                                    'reason',
                                    required: true,
                                    max: 1000,
                                  ),
                                  op,
                                ),
                                review:
                                    'Se conservará el antecedente. Las citas vinculadas siguen en Agenda; revisa allí si deben modificarse.',
                              ),
                              child: const Text('Retirar indicación'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Historial del carnet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Consulta por separado las vacunas y las desparasitaciones. Cada ficha conserva fecha, producto o cobertura, lote y próxima fecha cuando esos datos fueron registrados.',
            ),
            for (final type in const ['vacuna', 'desparasitación'])
              ExpansionTile(
                initiallyExpanded: true,
                tilePadding: EdgeInsets.zero,
                title: Text(type == 'vacuna' ? 'Vacunas' : 'Desparasitaciones'),
                subtitle: Text(
                  '${events.where((e) => e.data['type'] == type).length} registros',
                ),
                children: [
                  if (!events.any((e) => e.data['type'] == type))
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Sin registros en este apartado.'),
                      subtitle: Text(
                        'Esto no significa que no haya recibido aplicaciones.',
                      ),
                    ),
                  for (final event in events.where(
                    (e) => e.data['type'] == type,
                  ))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${event.data['coverage'] ?? event.data['product'] ?? (type == 'vacuna' ? 'Cobertura desconocida' : 'Tipo de desparasitación no especificado')}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            _bookletDetail(
                              'Fecha',
                              preventiveDateLabel(event.data),
                            ),
                            _bookletDetail(
                              'Origen',
                              preventiveOriginLabel(event.data),
                            ),
                            if ('${event.data['product'] ?? ''}'.isNotEmpty)
                              _bookletDetail(
                                'Producto',
                                '${event.data['product']}',
                              ),
                            if ('${event.data['batch'] ?? ''}'.isNotEmpty)
                              _bookletDetail('Lote', '${event.data['batch']}'),
                            if ('${event.data['performer'] ?? ''}'.isNotEmpty)
                              _bookletDetail(
                                'Aplicó',
                                '${event.data['performer']}',
                              ),
                            if ('${event.data['informant'] ?? ''}'.isNotEmpty)
                              _bookletDetail(
                                'Referido por',
                                '${event.data['informant']}',
                              ),
                            if (event.data['next_date'] != null)
                              _bookletDetail(
                                'Próxima fecha anotada',
                                '${event.data['next_date']} · confirmar vigencia antes de agendar',
                              ),
                            if ('${event.data['next_date_by'] ?? ''}'
                                .isNotEmpty)
                              _bookletDetail(
                                'Fecha indicada por',
                                '${event.data['next_date_by']}',
                              ),
                            if (model.data!['can_confirm'] == true)
                              TextButton(
                                onPressed: () => plan(event),
                                child: const Text(
                                  'Confirmar próxima fecha desde este antecedente',
                                ),
                              ),
                            for (final file
                                in model
                                    .rows('evidence')
                                    .where((f) => f['event_id'] == event.id))
                              TextButton.icon(
                                icon: const Icon(Icons.attach_file),
                                label: Text(
                                  '${file['label']} · ${(file['size'] as num) / 1024 ~/ 1} KB',
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PreventivePreview(
                                      load: () => widget.repository.evidence(
                                        widget.clinic,
                                        widget.patient,
                                        file['id'] as String,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (model.data!['can_attach'] == true)
                              TextButton.icon(
                                onPressed: () => attach(event),
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                                label: const Text(
                                  'Agregar foto o PDF escaneado',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    ),
  );
}

Widget _bookletDetail(String label, String value) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text('$label: $value'),
);

String appointmentLabel(dynamic state) => switch (state) {
  'agendado' => 'Agendada',
  'en_atencion' => 'En atención',
  'listo' => 'Lista',
  'entregado' => 'Entregada',
  'cancelado' => 'Cancelada',
  _ => 'Por comprobar',
};
String bookletError(Object error) {
  final text = error.toString();
  const labels = {
    'plan_already_scheduled':
        'La indicación ya tiene una cita vinculada. Actualiza y revísala en Agenda.',
    'plan_retired': 'La indicación ya fue retirada. Actualiza el carnet.',
    'plan_already_retired':
        'La indicación ya fue retirada. Actualiza el carnet.',
    'professional_confirmation_required':
        'La confirmación requiere permisos y verificación veterinaria vigentes.',
    'explicit_permission_required':
        'Necesitas permisos vigentes para esta acción.',
    'appointment_overlap': 'Ese integrante ya tiene una cita en ese horario.',
    'operation_payload_changed':
        'Cambió el contenido del intento. Abre de nuevo el formulario.',
  };
  for (final item in labels.entries) {
    if (text.contains(item.key)) return item.value;
  }
  return 'No se pudo guardar. Revisa la conexión, los datos y tus permisos; puedes reintentar sin duplicar el mismo registro.';
}
