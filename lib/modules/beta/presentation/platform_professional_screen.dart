import 'package:flutter/material.dart';
import '../domain/beta_repository.dart';

class PlatformProfessionalScreen extends StatefulWidget {
  const PlatformProfessionalScreen({super.key, required this.repository});
  final PlatformProfessionalRepository repository;
  @override
  State<PlatformProfessionalScreen> createState() =>
      _PlatformProfessionalScreenState();
}

class _PlatformProfessionalScreenState
    extends State<PlatformProfessionalScreen> {
  List<Map<String, dynamic>>? rows;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      rows = null;
    });
    try {
      final value = await widget.repository.globalProfessionalReviews();
      if (mounted) setState(() => rows = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo consultar. Revisa tu sesión de plataforma, 2FA y conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(Map<String, dynamic> row) async {
    if (busy) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RevocationDialog(name: '${row['name']} · ${row['license']}'),
    );
    if (reason == null || !mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.revokeGlobalProfessionalReview(
        row['id'] as String,
        reason,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          rows = null;
          error =
              'No se completó la revocación. Vuelve a verificar 2FA y consulta el estado antes de reintentar.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && error == null) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Habilitaciones globales')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Las verificaciones iniciales se registran fuera de la app después de revisar evidencia real. Aprobar una cuenta beta no acredita una cédula.',
        ),
        TextButton(
          onPressed: busy ? null : load,
          child: const Text('Actualizar habilitaciones'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (rows?.isEmpty == true)
          const Text('No hay verificaciones globales registradas.'),
        for (final row in rows ?? <Map<String, dynamic>>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${row['name']} · ${row['license']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('${row['email']}'),
                  Text(
                    row['revoked'] == true
                        ? 'Revocada'
                        : DateTime.tryParse(
                                '${row['valid_until']}',
                              )?.isAfter(DateTime.now()) ==
                              true
                        ? 'Verificación vigente'
                        : 'Verificación vencida',
                  ),
                  Text(
                    'Revisión: ${row['reviewed_at']}\nVence: ${row['valid_until']}\nRevisor: ${row['reviewer_id']}',
                  ),
                  SelectableText(
                    'Referencia: ${row['evidence_reference']}\nSHA-256: ${row['evidence_hash']}',
                  ),
                  if (row['revoked'] != true)
                    OutlinedButton(
                      onPressed: busy ? null : () => revoke(row),
                      child: const Text('Revocar verificación global'),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _RevocationDialog extends StatefulWidget {
  const _RevocationDialog({required this.name});
  final String name;
  @override
  State<_RevocationDialog> createState() => _RevocationDialogState();
}

class _RevocationDialogState extends State<_RevocationDialog> {
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Revocar habilitación global'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.name),
            const Text(
              'La revocación afecta las facultades que requieren esta verificación. Quedará registrada con tu identidad y hora del servidor.',
            ),
            TextFormField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Motivo'),
              maxLength: 1000,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Indica el motivo' : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, reason.text.trim());
          }
        },
        child: const Text('Confirmar revocación'),
      ),
    ],
  );
}
