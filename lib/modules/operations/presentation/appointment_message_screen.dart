import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../ai/domain/ai_repository.dart';
import '../../ai/presentation/request_ai_draft.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/domain/patient_contacts.dart';
import '../domain/operations_repository.dart';
import 'appointment_summary.dart';

class AppointmentMessageScreen extends StatefulWidget {
  const AppointmentMessageScreen({
    super.key,
    required this.repository,
    required this.member,
    required this.appointment,
    this.ai,
  });
  final ServiceContactRepository repository;
  final ClinicMembership member;
  final String appointment;
  final AiRepository? ai;
  @override
  State<AppointmentMessageScreen> createState() =>
      _AppointmentMessageScreenState();
}

class _AppointmentMessageScreenState extends State<AppointmentMessageScreen> {
  Map<String, dynamic>? data;
  final source = TextEditingController(),
      brief = TextEditingController(),
      message = TextEditingController();
  String purpose = 'appointment';
  bool busy = false,
      whatsapp = false,
      email = false,
      dirty = false,
      reviewed = false;
  String? error;
  int? draftVersion;
  Map<String, dynamic> preference(Map<String, dynamic> snapshot) =>
      Map<String, dynamic>.from(
        (snapshot['preferences'] as Map?)?[purpose] as Map? ?? {},
      );
  void setPreferences() {
    final p = preference(data!);
    whatsapp = p['whatsapp_allowed'] == true;
    email = p['email_allowed'] == true;
    source.text = '${p['consent_source'] ?? ''}';
    dirty = false;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    source.dispose();
    brief.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      data = null;
      reviewed = false;
      draftVersion = null;
      error = null;
    });
    try {
      final next = await widget.repository.appointmentContact(
        widget.member.clinicId,
        widget.appointment,
      );
      if (mounted) {
        setState(() {
          data = next;
          setPreferences();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo comprobar el contacto. Revisa permisos de citas y pacientes y SQL 14M.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveConsent() async {
    if (data?['owner_id'] == null) return;
    if ((whatsapp || email) && source.text.trim().length < 5) {
      setState(
        () => error = 'Indica cuándo y cómo el cliente autorizó este contacto.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      await widget.repository.saveServiceContact(
        widget.member.clinicId,
        '${data!['owner_id']}',
        purpose,
        whatsapp,
        email,
        source.text.trim(),
      );
      await load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo guardar la autorización. Revisa patient.write y SQL 14M.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> suggest() async {
    if (widget.ai == null || data == null) return;
    final snapshot = Map<String, dynamic>.from(data!);
    final response = await requestAiDraft(
      context,
      repository: widget.ai!,
      member: widget.member,
      title: purpose == 'appointment'
          ? 'Recordatorio de cita'
          : 'Seguimiento de atención',
      prompt:
          'Redacta un mensaje breve y amable de ${purpose == 'appointment' ? 'recordatorio de cita y confirmación de asistencia' : 'seguimiento después de la atención'}. '
          'Tipo de atención: ${appointmentKindLabel(snapshot['kind'])}. Horario registrado: ${snapshot['starts_local']} (${snapshot['timezone']}). '
          'Notas introducidas por el equipo para este mensaje: ${brief.text.trim()}. '
          'Usa un saludo genérico. Conserva las indicaciones del profesional sin añadir otras. No inventes ayuno, preparación, tratamientos, dosis, costos ni resultados. '
          'Si faltan instrucciones, pide al cliente comunicarse con la clínica. Devuelve solo un borrador de mensaje para revisión.',
    );
    if (!mounted || response == null) return;
    setState(() {
      message.text = response;
      draftVersion = snapshot['version'] as int;
      reviewed = false;
    });
  }

  Future<void> send(String channel) async {
    if (busy || dirty || !reviewed || message.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final fresh = await widget.repository.appointmentContact(
        widget.member.clinicId,
        widget.appointment,
      );
      final prefs = preference(fresh);
      if (fresh['owner_id'] != data?['owner_id']) {
        throw const FormatException(
          'Cambió el tutor vinculado. Actualiza y revisa el destinatario.',
        );
      }
      if (draftVersion != null && fresh['version'] != draftVersion) {
        throw const FormatException(
          'La cita cambió. Actualiza y vuelve a revisar el mensaje.',
        );
      }
      if (prefs[channel == 'whatsapp' ? 'whatsapp_allowed' : 'email_allowed'] !=
          true) {
        throw const FormatException(
          'No hay autorización vigente para este propósito y canal.',
        );
      }
      if (purpose == 'appointment' && fresh['state'] == 'cancelado') {
        throw const FormatException(
          'La cita está cancelada. Actualiza antes de redactar otro mensaje.',
        );
      }
      final uri = channel == 'whatsapp'
          ? contactWhatsapp('${fresh['phone'] ?? ''}', message.text.trim())
          : ('${fresh['email'] ?? ''}'.isEmpty
                ? null
                : Uri(
                    scheme: 'mailto',
                    path: '${fresh['email']}',
                    queryParameters: {
                      'subject': purpose == 'appointment'
                          ? 'Recordatorio de cita'
                          : 'Seguimiento de atención',
                      'body': message.text.trim(),
                    },
                  ));
      if (uri == null) {
        throw const FormatException(
          'No hay un contacto válido para este canal.',
        );
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException(
          'No se pudo abrir la aplicación de mensajería.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se pudo comprobar la autorización. No se abrió el envío.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mensajes de atención'),
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
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (data != null) ...[
          DropdownButtonFormField<String>(
            initialValue: purpose,
            items: const [
              DropdownMenuItem(
                value: 'appointment',
                child: Text('Recordatorio de cita'),
              ),
              DropdownMenuItem(
                value: 'follow_up',
                child: Text('Seguimiento de atención'),
              ),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    purpose = v!;
                    setPreferences();
                    message.clear();
                    reviewed = false;
                    draftVersion = null;
                  }),
          ),
          if (data!['owner_id'] == null)
            const Text(
              'Vincula la cita a un paciente con tutor registrado para guardar su autorización y usar estos mensajes.',
            )
          else ...[
            Text('Contacto: ${data!['name']}'),
            const Text(
              'Autorización para este tipo de mensaje. Es independiente del permiso para recibir promociones.',
            ),
            SwitchListTile(
              title: const Text('WhatsApp autorizado'),
              value: whatsapp,
              onChanged: busy || data!['can_record'] != true
                  ? null
                  : (v) => setState(() {
                      whatsapp = v;
                      dirty = true;
                    }),
            ),
            SwitchListTile(
              title: const Text('Correo autorizado'),
              value: email,
              onChanged: busy || data!['can_record'] != true
                  ? null
                  : (v) => setState(() {
                      email = v;
                      dirty = true;
                    }),
            ),
            TextField(
              controller: source,
              enabled: !busy && data!['can_record'] == true,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Cómo y cuándo autorizó el cliente',
              ),
              onChanged: (_) => setState(() => dirty = true),
            ),
            if (data!['can_record'] == true)
              OutlinedButton(
                onPressed: busy ? null : saveConsent,
                child: const Text('Guardar autorización'),
              ),
            TextField(
              controller: brief,
              enabled: !busy,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText:
                    'Indicaciones o contexto del profesional para el mensaje',
              ),
            ),
            if (widget.ai != null)
              OutlinedButton.icon(
                onPressed: busy ? null : suggest,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Redactar con IA'),
              ),
            TextField(
              key: const ValueKey('appointment-message'),
              controller: message,
              enabled: !busy,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Mensaje para revisar y editar',
              ),
              onChanged: (_) => setState(() {
                reviewed = false;
                draftVersion ??= data!['version'] as int;
              }),
            ),
            CheckboxListTile(
              title: const Text('Revisé el contenido y los datos de la cita'),
              value: reviewed,
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      reviewed = v == true;
                      if (reviewed) draftVersion = data!['version'] as int;
                    }),
            ),
            if (dirty)
              const Text('Guarda los cambios de autorización antes de enviar.'),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed:
                      busy ||
                          dirty ||
                          !reviewed ||
                          !whatsapp ||
                          message.text.trim().isEmpty
                      ? null
                      : () => send('whatsapp'),
                  child: const Text('Abrir WhatsApp'),
                ),
                OutlinedButton(
                  onPressed:
                      busy ||
                          dirty ||
                          !reviewed ||
                          !email ||
                          message.text.trim().isEmpty
                      ? null
                      : () => send('email'),
                  child: const Text('Abrir correo'),
                ),
              ],
            ),
            const Text(
              'Se abrirá el mensaje para que confirmes el envío en la aplicación elegida.',
            ),
          ],
        ],
      ],
    ),
  );
}
