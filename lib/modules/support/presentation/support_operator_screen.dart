import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/support_repository.dart';

class SupportOperatorEntry extends StatefulWidget {
  const SupportOperatorEntry({super.key, required this.repository});
  final SupportOperatorRepository repository;
  @override
  State<SupportOperatorEntry> createState() => _SupportOperatorEntryState();
}

class _SupportOperatorEntryState extends State<SupportOperatorEntry> {
  late final check = widget.repository.operatorEnabled();
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: check,
    builder: (context, s) => s.data != true
        ? const SizedBox.shrink()
        : TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    SupportOperatorScreen(repository: widget.repository),
              ),
            ),
            child: const Text('Panel de atención humana'),
          ),
  );
}

class SupportOperatorScreen extends StatefulWidget {
  const SupportOperatorScreen({super.key, required this.repository});
  final SupportOperatorRepository repository;
  @override
  State<SupportOperatorScreen> createState() => _SupportOperatorScreenState();
}

class _SupportOperatorScreenState extends State<SupportOperatorScreen> {
  final body = TextEditingController();
  List<Map<String, dynamic>> tickets = [];
  Map<String, dynamic>? detail;
  bool busy = false;
  String status = 'awaiting_user', operation = newOperationId();
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() f) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
    } catch (_) {
      if (mounted) {
        setState(() {
          detail = null;
          tickets = [];
          error = 'No se completó la atención. Revisa acceso y conexión.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async => run(() async {
    final rows = await widget.repository.queue();
    if (mounted) setState(() => tickets = rows);
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Atención humana')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Acceso de operador global de soporte. Las lecturas y respuestas quedan registradas. No uses esta información para otros fines.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        TextButton(
          onPressed: busy ? null : load,
          child: const Text('Actualizar pendientes'),
        ),
        for (final t in tickets)
          ListTile(
            title: Text(t['title'] as String),
            subtitle: Text('${t['category']} · ${t['status']}'),
            onTap: busy
                ? null
                : () => run(() async {
                    final d = await widget.repository.operatorDetail(
                      t['id'] as String,
                    );
                    if (mounted) {
                      setState(() {
                        detail = d;
                        body.clear();
                        operation = newOperationId();
                      });
                    }
                  }),
          ),
        if (detail != null) ...[
          Text(detail!['ticket']['title'] as String),
          Text(detail!['ticket']['body'] as String),
          for (final m in detail!['messages'] as List)
            ListTile(
              title: Text(m['body'] as String),
              subtitle: Text('${m['sender']} · ${m['created_at']}'),
            ),
          for (final a in detail!['attachments'] as List)
            TextButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final uri = await widget.repository.operatorDownload(
                        detail!['ticket']['id'] as String,
                        a['path'] as String,
                      );
                      if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw StateError('open');
                      }
                    }),
              child: Text(a['name'] as String),
            ),
          TextField(
            controller: body,
            enabled: !busy,
            onChanged: (_) => operation = newOperationId(),
            maxLength: 12000,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Respuesta humana'),
          ),
          DropdownButtonFormField<String>(
            initialValue: status,
            items: const [
              DropdownMenuItem(
                value: 'in_progress',
                child: Text('En revisión'),
              ),
              DropdownMenuItem(
                value: 'awaiting_user',
                child: Text('Esperando al usuario'),
              ),
              DropdownMenuItem(value: 'resolved', child: Text('Resuelto')),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    status = v!;
                    operation = newOperationId();
                  }),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    final id = detail!['ticket']['id'] as String;
                    await widget.repository.respond(
                      id,
                      body.text.trim(),
                      status,
                      operation,
                    );
                    final d = await widget.repository.operatorDetail(id);
                    if (mounted) {
                      setState(() {
                        detail = d;
                        body.clear();
                      });
                    }
                  }),
            child: const Text('Responder como soporte'),
          ),
        ],
      ],
    ),
  );
}
