import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/clinic_membership.dart';
import 'auth_view_model.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, required this.model, required this.clinic});
  final AuthViewModel model;
  final ClinicMembership clinic;
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  Map<String, dynamic>? snapshot;
  String? error;
  bool busy = false;
  TeamRepository get repository => widget.model.repository as TeamRepository;
  bool get allowed =>
      !widget.model.offline &&
      widget.model.memberships.any(
        (m) =>
            m.clinicId == widget.clinic.clinicId &&
            m.role == ClinicRole.admin &&
            !m.isPersonal,
      );
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!allowed || busy) return;
    setState(() {
      busy = true;
      error = null;
      snapshot = null;
    });
    try {
      final result = await repository.team(widget.clinic.clinicId);
      if (mounted && allowed) setState(() => snapshot = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo consultar el equipo. Actualiza tus permisos y revisa la conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(String title, Future<void> Function() action) async {
    if (!allowed || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
          'El cambio afecta el acceso a esta clínica. Quedará registrado en la bitácora.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !allowed || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await widget.model.refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          snapshot = null;
          error = e.toString().contains('last_admin_required')
              ? 'La clínica debe conservar al menos un administrador. Asigna otro antes de continuar.'
              : 'No se completó el cambio. Actualiza el equipo y revisa tus permisos.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && error == null && allowed) await load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Equipo e invitaciones')),
      body: !allowed
          ? const Center(
              child: Text(
                'Actualiza el acceso. Esta gestión requiere un administrador conectado.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.clinic.clinicName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'El rol de acceso no acredita la habilitación profesional para actos reservados.',
                ),
                OutlinedButton(
                  onPressed: busy ? null : load,
                  child: const Text('Actualizar equipo'),
                ),
                if (busy) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                const Text('Integrantes'),
                for (final m in snapshot?['members'] as List? ?? [])
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(m['email'] ?? m['user_id']),
                          if (m['user_id'] == widget.model.repository.userId)
                            const Text('Tu cuenta'),
                          DropdownButtonFormField<ClinicRole>(
                            key: ValueKey('${m['user_id']}-${m['role']}'),
                            initialValue: ClinicRole.parse(m['role']),
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Rol en la clínica',
                            ),
                            items: [
                              for (final r in ClinicRole.values)
                                DropdownMenuItem(
                                  value: r,
                                  child: Text(r.label),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (role) async {
                                    if (role == null ||
                                        role.name == m['role']) {
                                      return;
                                    }
                                    await change(
                                      'Cambiar rol a ${role.label}',
                                      () => repository.setMemberRole(
                                        widget.clinic.clinicId,
                                        m['user_id'],
                                        role,
                                      ),
                                    );
                                    // Restore the authoritative selection after a cancelled confirmation.
                                    if (mounted && allowed && error == null) {
                                      await load();
                                    }
                                  },
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => change(
                                    'Dar de baja a ${m['email'] ?? 'esta persona'}',
                                    () => repository.removeMember(
                                      widget.clinic.clinicId,
                                      m['user_id'],
                                    ),
                                  ),
                            child: const Text('Dar de baja de esta clínica'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Text('Invitaciones'),
                for (final i in snapshot?['invitations'] as List? ?? [])
                  ListTile(
                    title: Text(i['email']),
                    subtitle: Text(
                      '${ClinicRole.parse(i['role']).label} · ${invitationState(i)}',
                    ),
                    trailing: invitationState(i) == 'Pendiente'
                        ? TextButton(
                            onPressed: busy
                                ? null
                                : () => change(
                                    'Revocar invitación',
                                    () => repository.revokeInvitation(i['id']),
                                  ),
                            child: const Text('Revocar'),
                          )
                        : null,
                  ),
              ],
            ),
    ),
  );
}

String invitationState(Map<dynamic, dynamic> invitation) {
  if (invitation['accepted_at'] != null) return 'Aceptada';
  if (invitation['revoked_at'] != null) return 'Revocada';
  final expiry = DateTime.tryParse('${invitation['expires_at']}');
  if (expiry == null || !expiry.isAfter(DateTime.now().toUtc())) {
    return 'Vencida';
  }
  return 'Pendiente';
}
