import 'ai_labels.dart';
import 'package:flutter/material.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/ai_repository.dart';

const starterTopics = <String, String>{
  'getting_started': 'Primeros pasos',
  'permissions': 'Roles y permisos',
  'payments': 'Planes, ventas y caja',
  'notifications': 'Avisos y notificaciones',
  'report_problem': 'Reportar un problema',
  'privacy': 'Privacidad y contexto',
};

class StarterHelpPanel extends StatefulWidget {
  const StarterHelpPanel({
    super.key,
    required this.repository,
    required this.clinic,
    required this.onCompleted,
  });
  final StarterAiRepository repository;
  final String clinic;
  final Future<void> Function(String) onCompleted;
  @override
  State<StarterHelpPanel> createState() => _StarterHelpPanelState();
}

class _StarterHelpPanelState extends State<StarterHelpPanel> {
  Map<String, dynamic>? data;
  String topic = 'getting_started';
  bool consent = false, busy = false;
  String? error;
  String operation = newOperationId();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await widget.repository.starterStatus(widget.clinic);
      if (mounted) {
        setState(() {
          data = d;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          data = null;
          error = 'La ayuda incluida todavía no está disponible.';
        });
      }
    }
  }

  Future<void> send() async {
    if (busy || !consent) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await widget.repository.starterHelp(
        widget.clinic,
        topic,
        operation,
      );
      if (!mounted) return;
      operation = newOperationId();
      consent = false;
      await widget.onCompleted(id);
      await load();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se completó la consulta. Actualiza para revisar disponibilidad y cuota.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ayuda IA incluida',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Sin API key propia. Elige un tema de uso de la app. Solo se envía ese tema y la guía pública; no se envían tus mensajes, expedientes, adjuntos ni otros chats. No ofrece asesoría clínica.',
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (data == null || data!['enabled'] != true)
            const Text(
              'La ayuda incluida aún no está activada. Puedes continuar con la guía o consultar soporte.',
            ),
          if (data != null)
            Text(
              'Proveedor: ${aiProviderLabels[data!['provider']] ?? data!['provider']} · modelo: ${data!['model']} · intentos hoy (UTC): ${data!['used']} / ${data!['limit']}',
            ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: topic,
            decoration: const InputDecoration(labelText: 'Tema de ayuda'),
            items: starterTopics.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) => setState(() {
                    topic = v!;
                    consent = false;
                    operation = newOperationId();
                  }),
          ),
          CheckboxListTile(
            value: consent,
            onChanged: busy
                ? null
                : (v) => setState(() => consent = v ?? false),
            title: const Text(
              'Autorizo consultar este tema de la guía con el proveedor indicado.',
            ),
          ),
          FilledButton(
            onPressed: busy || !consent || data?['enabled'] != true
                ? null
                : send,
            child: const Text('Consultar ayuda incluida'),
          ),
          if (error != null)
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      setState(() {
                        operation = newOperationId();
                        consent = false;
                        error = null;
                      });
                      load();
                    },
              child: const Text('Preparar nueva consulta (usa cuota)'),
            ),
          TextButton(
            onPressed: busy ? null : load,
            child: const Text('Actualizar disponibilidad'),
          ),
          const Text(
            'Respuesta orientativa, guardada en un chat privado. Sujeta a disponibilidad y límites del proveedor. No cambia automáticamente a modelos de pago.',
          ),
        ],
      ),
    ),
  );
}
