import 'platform_professional_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../domain/beta_repository.dart';

class PlatformBetaScreen extends StatefulWidget {
  const PlatformBetaScreen({
    super.key,
    required this.repository,
    required this.mfaReady,
    required this.onSignOut,
    required this.onVerified,
  });
  final BetaRepository repository;
  final bool mfaReady;
  final Future<void> Function() onSignOut, onVerified;
  @override
  State<PlatformBetaScreen> createState() => _PlatformBetaScreenState();
}

class _PlatformBetaScreenState extends State<PlatformBetaScreen> {
  final email = TextEditingController(),
      reason = TextEditingController(),
      code = TextEditingController();
  Map<String, dynamic>? data;
  BetaMfaSetup? setup;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.mfaReady) load();
  }

  @override
  void didUpdateWidget(covariant PlatformBetaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.mfaReady && widget.mfaReady) {
      setup = null;
      code.clear();
      load();
    }
  }

  @override
  void dispose() {
    email.dispose();
    reason.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se completó la operación. Revisa 2FA, datos y conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    try {
      final value = await widget.repository.administration();
      if (mounted) setState(() => data = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo consultar la administración. Verifica 2FA y acceso.',
        );
      }
    }
  }

  Future<void> createInvite() async {
    final result = await widget.repository.invite(email.text.trim(), 24);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invitación · visible una sola vez'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Válida por 24 horas y ligada al correo indicado. Guarda el código antes de cerrar.',
              ),
              SelectableText(result['token'] as String),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(
              ClipboardData(text: result['token'] as String),
            ),
            child: const Text('Copiar código'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Administración de plataforma'),
      actions: [
        TextButton(
          onPressed: busy ? null : widget.onSignOut,
          child: const Text('Salir'),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Cuenta separada de las clínicas. Aprobar acceso beta no verifica una cédula ni concede permisos clínicos.',
              ),
              if (error != null) Text(error!),
              if (!widget.mfaReady) ...[
                const SizedBox(height: 16),
                const Text(
                  'Completa el segundo factor para administrar la plataforma.',
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final value = await widget.repository.prepareMfa();
                          if (mounted) setState(() => setup = value);
                        }),
                  child: const Text('Preparar 2FA'),
                ),
                if (setup?.uri != null)
                  Center(
                    child: QrImageView(
                      data: setup!.uri!,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                if (setup?.secret != null) ...[
                  const Text(
                    'Clave para tu autenticador. No la compartas por chat.',
                  ),
                  SelectableText(setup!.secret!),
                ],
                if (setup != null) ...[
                  TextField(
                    controller: code,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Código del autenticador',
                    ),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await widget.repository.verifyMfa(
                              setup!.factorId,
                              code.text.trim(),
                            );
                            code.clear();
                            await widget.onVerified();
                          }),
                    child: const Text('Verificar 2FA'),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 16),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Correo de la persona',
                  ),
                ),
                TextField(
                  controller: reason,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText:
                        'Motivo de aprobación o revocación (mínimo 5 caracteres)',
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              await widget.repository.setEmail(
                                email.text,
                                true,
                                reason.text,
                              );
                              await load();
                            }),
                      child: const Text('Aprobar correo'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              await widget.repository.setEmail(
                                email.text,
                                false,
                                reason.text,
                              );
                              await load();
                            }),
                      child: const Text('Revocar correo'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : () => run(createInvite),
                      child: const Text('Invitación de un uso · 24 h'),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => run(load),
                      child: const Text('Actualizar'),
                    ),
                  ],
                ),
                if (widget.repository is PlatformProfessionalRepository)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PlatformProfessionalScreen(
                                repository:
                                    widget.repository
                                        as PlatformProfessionalRepository,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Habilitaciones profesionales globales'),
                  ),
                for (final section in [
                  'approvals',
                  'invites',
                  'enrollments',
                ]) ...[
                  const Divider(),
                  Text(
                    {
                      'approvals': 'Correos aprobados / revocados',
                      'invites': 'Invitaciones',
                      'enrollments': 'Inscripciones',
                    }[section]!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final row in (data?[section] as List? ?? []).cast<Map>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${row['email']}'),
                      subtitle: Text(
                        section == 'approvals'
                            ? (row['enabled'] == true ? 'Aprobado' : 'Revocado')
                            : section == 'invites'
                            ? 'Vence: ${row['expires_at']} · ${row['revoked_at'] != null
                                  ? 'revocada'
                                  : row['consumed_at'] != null
                                  ? 'usada'
                                  : 'pendiente'}'
                            : 'Vence: ${row['expires_at']} · ${row['revoked_at'] != null ? 'revocada' : 'inscrita'}',
                      ),
                      trailing:
                          section == 'invites' && row['revoked_at'] == null
                          ? IconButton(
                              tooltip: 'Revocar invitación',
                              onPressed: busy
                                  ? null
                                  : () => run(() async {
                                      await widget.repository.revokeInvite(
                                        row['id'] as String,
                                        reason.text,
                                      );
                                      await load();
                                    }),
                              icon: const Icon(Icons.block),
                            )
                          : null,
                    ),
                ],
              ],
              if (busy) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    ),
  );
}
