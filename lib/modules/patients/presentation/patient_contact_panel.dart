import 'package:flutter/material.dart';
import '../domain/patient_contacts.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import 'contact_actions.dart';

class PatientContactPanel extends StatefulWidget {
  const PatientContactPanel({
    super.key,
    required this.repository,
    required this.clinic,
    required this.patient,
    required this.patientName,
    required this.onSaved,
  });
  final PatientContactRepository repository;
  final String clinic, patient, patientName;
  final Future<void> Function() onSaved;
  @override
  State<PatientContactPanel> createState() => _PatientContactPanelState();
}

class _PatientContactPanelState extends State<PatientContactPanel>
    with WidgetsBindingObserver {
  Map<String, dynamic>? data;
  bool busy = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      load();
    } else {
      generation++;
      if (mounted) {
        setState(() {
          data = null;
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    generation++;
    data = null;
    super.dispose();
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      busy = true;
      data = null;
      error = null;
    });
    try {
      final next = await widget.repository.contact(
        widget.clinic,
        widget.patient,
      );
      if (next['schema_version'] != 1 ||
          next['clinic_id'] != widget.clinic ||
          next['patient_id'] != widget.patient) {
        throw const FormatException('Contrato de contactos no compatible.');
      }
      if (mounted && request == generation) setState(() => data = next);
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error =
              'No se pudieron comprobar los contactos adicionales ni la bitácora. Actualiza antes de editar.',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  Future<void> form(bool log) async {
    final owner = Map<String, dynamic>.from(data!['owner'] as Map);
    final repo = widget.repository,
        clinic = widget.clinic,
        patient = widget.patient;
    final ownerId = owner['id'] as String;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: log ? 'Registrar intento de contacto' : 'Contacto del tutor',
          initial: log
              ? {'occurred_at': DateTime.now().toUtc().toIso8601String()}
              : {
                  for (final key in [
                    'name',
                    'phone',
                    'phone_alt',
                    'email',
                    'address',
                    'contact_name',
                    'contact_phone',
                    'contact_relationship',
                    'contact_authorized',
                  ])
                    key: owner[key],
                },
          fields: log
              ? const [
                  RxField(
                    'recipient',
                    'Persona o número contactado',
                    required: true,
                  ),
                  RxField(
                    'method',
                    'Medio',
                    type: 'select',
                    required: true,
                    options: {
                      'llamada': 'Llamada',
                      'whatsapp': 'WhatsApp',
                      'presencial': 'Presencial',
                      'otro': 'Otro',
                    },
                  ),
                  RxField(
                    'outcome',
                    'Resultado',
                    type: 'select',
                    required: true,
                    options: {
                      'contactado': 'Contacto establecido',
                      'sin_respuesta': 'Sin respuesta',
                      'no_disponible': 'Número no disponible',
                      'otro': 'Otro / aclaración',
                    },
                  ),
                  RxField(
                    'occurred_at',
                    'Fecha y hora del intento',
                    type: 'local_instant',
                    required: true,
                  ),
                  RxField(
                    'notes',
                    'Observaciones de comunicación (sin diagnóstico)',
                    type: 'text',
                  ),
                ]
              : const [
                  RxField('name', 'Nombre del tutor', required: true),
                  RxField('phone', 'Teléfono principal (+país)'),
                  RxField(
                    'phone_alt',
                    'Teléfono alternativo del tutor (+país)',
                  ),
                  RxField('email', 'Correo'),
                  RxField('address', 'Dirección', type: 'text'),
                  RxField('contact_name', 'Nombre del contacto adicional'),
                  RxField(
                    'contact_phone',
                    'Teléfono del contacto adicional (+país)',
                  ),
                  RxField('contact_relationship', 'Relación con el tutor'),
                  RxField(
                    'contact_authorized',
                    'El tutor autoriza contactar a esta persona',
                    type: 'checkbox',
                  ),
                ],
          submit: (values, operation) async {
            if (!mounted) {
              throw const FormatException(
                'El espacio cambió. Abre el contacto de nuevo.',
              );
            }
            if (log) {
              await repo.logContact(
                clinic,
                patient,
                ownerId,
                values,
                operation,
              );
            } else {
              await repo.saveContact(
                clinic,
                patient,
                ownerId,
                owner['contact_version'] as int,
                values,
                operation,
              );
            }
          },
        ),
      ),
    );
    if (!mounted || result != true) return;
    if (!log) await widget.onSaved();
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final owner = data?['owner'] is Map
        ? Map<String, dynamic>.from(data!['owner'] as Map)
        : <String, dynamic>{};
    final logs = (data?['attempts'] as List? ?? const []).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data?['owner'] is Map)
          ContactActions(owner: owner, patientName: widget.patientName),
        if (data != null && data?['owner'] is! Map)
          const Text('Tutor pendiente de capturar.'),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: busy ? null : load,
              child: const Text('Actualizar contacto'),
            ),
            if (data?['can_write'] == true && data?['owner'] is Map) ...[
              TextButton(
                onPressed: busy ? null : () => form(false),
                child: const Text('Editar contacto del tutor'),
              ),
              TextButton(
                onPressed: busy ? null : () => form(true),
                child: const Text('Registrar intento de contacto'),
              ),
            ],
          ],
        ),
        if (data != null)
          ExpansionTile(
            title: const Text('Bitácora de contacto'),
            children: [
              if (logs.isEmpty)
                const ListTile(
                  title: Text('Sin intentos registrados. No implica abandono.'),
                ),
              for (final log in logs)
                ListTile(
                  title: Text(
                    '${log['method']} · ${log['outcome']} · ${log['recipient']}',
                  ),
                  subtitle: Text(
                    '${log['occurred_at']} · ${log['notes']}\nCapturó: ${log['recorded_by']} · ${log['created_at']}',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
