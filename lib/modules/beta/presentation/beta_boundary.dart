import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/beta_repository.dart';
import 'platform_beta_screen.dart';

class BetaBoundary extends StatefulWidget {
  const BetaBoundary({
    super.key,
    required this.repository,
    required this.child,
    required this.onSignOut,
    required this.onRefresh,
    this.clinicId,
    this.canSponsor = false,
  });
  final BetaRepository repository;
  final Widget child;
  final String? clinicId;
  final bool canSponsor;
  final Future<void> Function() onSignOut, onRefresh;
  @override
  State<BetaBoundary> createState() => _BetaBoundaryState();
}

class _BetaBoundaryState extends State<BetaBoundary> {
  BetaState? state;
  bool busy = false, accepted = false, privacyRead = false;
  bool entered = false, termsReadOnly = false;
  String? error;
  final token = TextEditingController();
  Timer? timer;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  @override
  void didUpdateWidget(covariant BetaBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) {
      state = null;
      refresh();
    }
  }

  @override
  void dispose() {
    revision++;
    timer?.cancel();
    token.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final request = ++revision;
    try {
      final value = await widget.repository.status(widget.clinicId);
      if (!mounted || request != revision) return;
      setState(() {
        if (value.terms?['hash'] != state?.terms?['hash'] ||
            value.terms?['version'] != state?.terms?['version'] ||
            value.privacy?['version'] != state?.privacy?['version'] ||
            value.privacy?['hash'] != state?.privacy?['hash']) {
          accepted = false;
          privacyRead = false;
          termsReadOnly = false;
        }
        state = value;
        error = null;
      });
    } catch (_) {
      if (mounted && request == revision) {
        setState(
          () => error =
              'No se pudo verificar el acceso beta. Conéctate e intenta de nuevo.',
        );
      }
    }
  }

  Future<void> run(
    Future<void> Function() action, {
    bool refreshMemberships = true,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await refresh();
      if (refreshMemberships) await widget.onRefresh();
    } catch (failure) {
      await refresh();
      if (mounted) {
        setState(
          () => error =
              (failure.toString().contains('beta_terms_changed') ||
                  failure.toString().contains('beta_privacy_changed'))
              ? 'Los términos cambiaron o se actualizó el aviso de privacidad. Revisa los textos actuales y confirma de nuevo.'
              : 'No se completó la operación. Revisa correo aprobado, invitación, términos y conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = state;
    if (value?.platform == true) {
      return PlatformBetaScreen(
        repository: widget.repository,
        mfaReady: value!.mfaReady,
        onSignOut: widget.onSignOut,
        onVerified: refresh,
      );
    }
    if (value?.canEnter == true && value!.termsPending && !termsReadOnly) {
      return frame(
        Scaffold(
          appBar: AppBar(
            title: const Text('Términos actualizados'),
            actions: [
              TextButton(
                onPressed: busy ? null : widget.onSignOut,
                child: const Text('Salir'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Lee y acepta la nueva versión para registrar cambios. Puedes seguir consultando y exportando sin ampliar la duración de tu beta.',
              ),
              if (error != null) Text(error!),
              if (value.terms != null) ...[
                ...termsFields(value),
                FilledButton(
                  onPressed:
                      busy ||
                          !accepted ||
                          (value.privacy != null && !privacyRead)
                      ? null
                      : () => run(
                          () => widget.repository.acceptTerms(
                            value.terms!['version'] as String,
                            value.terms!['hash'] as String,
                            privacyVersion:
                                value.privacy?['version'] as String?,
                            privacyHash: value.privacy?['hash'] as String?,
                          ),
                          refreshMemberships: false,
                        ),
                  child: Text('Aceptar versión ${value.terms!['version']}'),
                ),
              ],
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => termsReadOnly = true),
                child: const Text('Continuar solo consulta y exportación'),
              ),
              TextButton(
                onPressed: busy ? null : refresh,
                child: const Text('Revisar acceso'),
              ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      );
    }
    if (value?.canEnter == true && error == null) {
      final banner = value!.termsPending
          ? 'Términos pendientes de aceptación. Solo consulta y exportación.'
          : value.data['update_required'] == true
          ? 'Esta versión requiere actualización. Puedes consultar y exportar; solicita el APK actualizado.'
          : value.readOnly
          ? 'Beta en modo consulta y exportación. No se permiten nuevos registros.'
          : value.warning
          ? 'Tu beta vence en los próximos 7 días.'
          : value.mode == 'sponsor_grace'
          ? 'La clínica tiene una gracia de 14 días para regularizar su patrocinador.'
          : value.mode == 'internal'
          ? 'Pruebas internas · admisiones beta cerradas'
          : null;
      return frame(null, banner: banner);
    }
    return frame(
      Scaffold(
        appBar: AppBar(
          title: const Text('Acceso a la beta'),
          actions: [
            TextButton(
              onPressed: busy ? null : widget.onSignOut,
              child: const Text('Salir'),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (value == null && error == null)
                  const Center(child: CircularProgressIndicator()),
                if (error != null) Text(error!),
                if (value?.mode == 'email_review_required')
                  const Text(
                    'Tu correo cambió o necesita confirmación. Solicita revisión a administración.',
                  ),
                if (value?.mode == 'denied')
                  const Text('No tienes acceso a esta clínica.'),
                if (value?.mode == 'revoked')
                  const Text(
                    'Tu acceso beta fue revocado. Consulta con administración de plataforma.',
                  ),
                if (value?.mode == 'sponsor_required') ...[
                  const Text(
                    'La clínica necesita un patrocinador beta con acceso vigente.',
                  ),
                  if (widget.canSponsor && widget.clinicId != null)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => run(
                              () => widget.repository.sponsor(widget.clinicId!),
                            ),
                      child: const Text('Aceptar patrocinio de esta clínica'),
                    ),
                ],
                if (value?.mode == 'not_enrolled') ...[
                  Text(
                    value!.admissionsOpen
                        ? 'Acceso solo con correo aprobado o invitación.'
                        : 'Las admisiones beta todavía están cerradas.',
                  ),
                  if (value.admissionsOpen && value.terms != null) ...[
                    const SizedBox(height: 16),
                    ...termsFields(value),
                    TextField(
                      controller: token,
                      decoration: const InputDecoration(
                        labelText: 'Invitación, si tu correo no está aprobado',
                      ),
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                    FilledButton(
                      onPressed:
                          busy ||
                              !accepted ||
                              (value.privacy != null && !privacyRead)
                          ? null
                          : () => run(
                              () => widget.repository.enroll(
                                value.terms!['version'] as String,
                                value.terms!['hash'] as String,
                                token.text.trim().isEmpty
                                    ? null
                                    : token.text.trim(),
                                privacyVersion:
                                    value.privacy?['version'] as String?,
                                privacyHash: value.privacy?['hash'] as String?,
                              ),
                            ),
                      child: const Text('Ingresar a la beta'),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: busy ? null : refresh,
                  child: const Text('Revisar acceso'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> termsFields(BetaState value) => [
    Text(
      'Términos de uso · versión ${value.terms!['version']}',
      style: Theme.of(context).textTheme.titleLarge,
    ),
    const SizedBox(height: 12),
    SelectableText(value.terms!['content'] as String),
    if (value.privacy != null) ...[
      const SizedBox(height: 20),
      Text(
        'Aviso de privacidad · versión ${value.privacy!['version']}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      SelectableText(value.privacy!['content'] as String),
      CheckboxListTile(
        value: privacyRead,
        onChanged: busy
            ? null
            : (v) => setState(() => privacyRead = v ?? false),
        title: Text(
          'Leí el aviso de privacidad versión ${value.privacy!['version']}',
        ),
      ),
    ],
    CheckboxListTile(
      value: accepted,
      onChanged: busy ? null : (v) => setState(() => accepted = v ?? false),
      title: Text(
        'Leí y acepto la versión ${value.terms!['version']} de estos términos',
      ),
    ),
  ];

  Widget frame(Widget? blocked, {String? banner}) {
    if (blocked == null) entered = true;
    return Stack(
      children: [
        if (entered)
          Positioned.fill(
            key: const ValueKey('beta-workspace'),
            child: Offstage(
              offstage: blocked != null,
              child: Column(
                children: [
                  if (banner != null)
                    SafeArea(
                      bottom: false,
                      child: Material(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(banner),
                        ),
                      ),
                    ),
                  if (state?.termsPending == true)
                    TextButton(
                      onPressed: () => setState(() => termsReadOnly = false),
                      child: const Text('Leer y aceptar términos actualizados'),
                    ),
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ),
        if (blocked != null)
          Positioned.fill(key: const ValueKey('beta-blocked'), child: blocked),
      ],
    );
  }
}
