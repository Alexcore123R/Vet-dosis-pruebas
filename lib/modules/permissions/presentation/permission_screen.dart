import 'package:flutter/material.dart';
import '../../auth/presentation/auth_view_model.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/permission_repository.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({
    super.key,
    required this.model,
    required this.clinic,
  });
  final AuthViewModel model;
  final ClinicMembership clinic;
  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  Map<String, dynamic>? data, evidence;
  bool busy = false;
  String? error;
  PermissionRepository get repository =>
      widget.model.repository as PermissionRepository;
  bool get allowed =>
      !widget.model.offline &&
      widget.model.repository.userId == widget.clinic.userId &&
      widget.model.memberships.any((m) => m.clinicId == widget.clinic.clinicId);
  List<Map> rows(String key, [Map<String, dynamic>? source]) =>
      ((source ?? data)?[key] as List? ?? []).cast<Map>();
  bool get manager => data?['can_manage'] == true;
  bool get reviewer => data?['can_review'] == true;
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
      data = null;
      evidence = null;
    });
    try {
      final results = await Future.wait([
        repository.permissions(widget.clinic.clinicId),
        repository.professionalEvidence(widget.clinic.clinicId),
      ]);
      if (mounted && allowed) {
        setState(() {
          data = results[0];
          evidence = results[1];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo consultar permisos y habilitación. Revisa tu acceso y conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(Future<void> Function() action) async {
    if (!allowed || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          data = null;
          evidence = null;
          error =
              'No se guardó el cambio. Revisa permisos, vigencia y evidencia; vuelve a consultar.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && error == null) await load();
  }

  Future<Map<String, String>?> edit(
    String title,
    List<(String, String)> fields, {
    String? explanation,
  }) async {
    final controllers = {for (final f in fields) f.$1: TextEditingController()};
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (explanation != null) Text(explanation),
                for (final f in fields)
                  TextFormField(
                    controller: controllers[f.$1],
                    decoration: InputDecoration(labelText: f.$2),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Campo obligatorio';
                      }
                      if (f.$1 == 'until' || f.$1 == 'reviewed') {
                        final date = DateTime.tryParse(v.trim());
                        if (date == null) {
                          return 'Usa fecha y hora: AAAA-MM-DD HH:MM';
                        }
                        if (f.$1 == 'until' && !date.isAfter(DateTime.now())) {
                          return 'Elige una vigencia futura';
                        }
                        if (f.$1 == 'reviewed' &&
                            date.isAfter(DateTime.now())) {
                          return 'La revisión no puede ser futura';
                        }
                      }
                      if (f.$1 == 'hash' &&
                          !RegExp(r'^[a-f0-9]{64}$').hasMatch(v.trim())) {
                        return 'SHA-256: 64 caracteres hexadecimales';
                      }
                      return null;
                    },
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
                Navigator.pop(context, {
                  for (final e in controllers.entries)
                    e.key: e.value.text.trim(),
                });
              }
            },
            child: const Text('Revisar cambio'),
          ),
        ],
      ),
    );
    // Dialog route finishes its exit animation before disposing its controllers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final c in controllers.values) {
      c.dispose();
    }
    if (result == null || !mounted || !allowed) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            '${explanation ?? 'El cambio quedará registrado con tu cuenta y hora del servidor.'}\n\n${fields.map((f) => '${f.$2}: ${result[f.$1]}').join('\n')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar cambio'),
          ),
        ],
      ),
    );
    return confirmed == true ? result : null;
  }

  Future<void> grant(Map member) async {
    Map? selected;
    String? procedure;
    final selectedCode = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Elegir permiso'),
        children: [
          for (final c in rows('catalog'))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c['code'] as String),
              child: Text(
                '${c['label']}${c['requires_professional'] == true ? ' · requiere habilitación' : ''}',
              ),
            ),
        ],
      ),
    );
    if (selectedCode == null || !mounted) return;
    selected = rows('catalog').firstWhere((c) => c['code'] == selectedCode);
    if (selected['procedure_scoped'] == true) {
      procedure = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Tipo de procedimiento obligatorio'),
          children: [
            for (final p in rows(
              'procedures',
            ).where((p) => p['active'] == true))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p['id'] as String),
                child: Text(p['name'] as String),
              ),
            if (!rows('procedures').any((p) => p['active'] == true))
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Primero registra un tipo de procedimiento.'),
              ),
          ],
        ),
      );
      if (procedure == null || !mounted) return;
    }
    final procedureName = procedure == null
        ? ''
        : rows('procedures').firstWhere((p) => p['id'] == procedure)['name'];
    final values = await edit(
      'Conceder permiso',
      [('until', 'Vence (AAAA-MM-DD HH:MM, hora local)'), ('reason', 'Motivo')],
      explanation:
          '${member['email']}\n${selected['label']}\n$procedureName\nNo otorga habilitación profesional.',
    );
    if (values != null) {
      await change(
        () => repository.grantPermission(
          widget.clinic.clinicId,
          member['user_id'] as String,
          selectedCode,
          procedure,
          DateTime.parse(values['until']!),
          values['reason']!,
        ),
      );
    }
  }

  String memberName(Object? id) =>
      '${rows('members').where((m) => m['user_id'] == id).firstOrNull?['email'] ?? id}';
  String procedureName(Object? id) =>
      '${rows('procedures').where((p) => p['id'] == id).firstOrNull?['name'] ?? id ?? 'General'}';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Permisos y habilitación')),
      body: !allowed
          ? const Center(
              child: Text(
                'Actualiza tu sesión. Esta consulta requiere conexión y membresía vigente.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.clinic.clinicName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (data != null && data!['enforcement_enabled'] != true)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'La beta sigue en preparación. Configura los permisos de cada persona; el puesto no concede acceso.',
                      ),
                    ),
                  ),
                const Text(
                  'El puesto es una etiqueta visual. Los permisos y la habilitación se revisan por separado.',
                ),
                TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('Actualizar permisos'),
                ),
                if (busy) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                for (final m in rows('members'))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m['email']}'),
                          Text(
                            'Puesto: ${m['job_label'] == '' ? 'Sin etiqueta' : m['job_label']}',
                          ),
                          Text(
                            m['professional_current'] == true
                                ? 'Habilitación vigente'
                                : 'Sin habilitación vigente',
                          ),
                          if (manager)
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          final v = await edit(
                                            'Etiqueta de puesto',
                                            [('label', 'Puesto (solo visual)')],
                                          );
                                          if (v != null) {
                                            await change(
                                              () => repository.setJobLabel(
                                                widget.clinic.clinicId,
                                                m['user_id'] as String,
                                                v['label']!,
                                              ),
                                            );
                                          }
                                        },
                                  child: const Text('Editar puesto'),
                                ),
                                TextButton(
                                  onPressed: busy ? null : () => grant(m),
                                  child: const Text('Conceder permiso'),
                                ),
                                if (m['professional_current'] == true)
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            final v = await edit(
                                              'Proponer responsable',
                                              [
                                                (
                                                  'until',
                                                  'Vence (AAAA-MM-DD HH:MM, hora local)',
                                                ),
                                              ],
                                              explanation:
                                                  '${m['email']} deberá aceptar la responsabilidad desde su cuenta.',
                                            );
                                            if (v != null) {
                                              await change(
                                                () => repository
                                                    .proposeResponsible(
                                                      widget.clinic.clinicId,
                                                      m['user_id'] as String,
                                                      DateTime.parse(
                                                        v['until']!,
                                                      ),
                                                    ),
                                              );
                                            }
                                          },
                                    child: const Text('Proponer responsable'),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (manager) ...[
                  const Divider(),
                  const Text('Tipos de procedimiento'),
                  const Text(
                    'Solo identifican el alcance; no contienen dosis ni protocolos.',
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final v = await edit(
                              'Registrar tipo de procedimiento',
                              [('name', 'Nombre')],
                            );
                            if (v != null) {
                              await change(
                                () => repository.setProcedure(
                                  widget.clinic.clinicId,
                                  null,
                                  v['name']!,
                                  true,
                                ),
                              );
                            }
                          },
                    child: const Text('Agregar tipo de procedimiento'),
                  ),
                  for (final p in rows('procedures'))
                    ListTile(
                      title: Text('${p['name']}'),
                      subtitle: Text(
                        p['active'] == true ? 'Activo' : 'Inactivo',
                      ),
                      trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final v = await edit(
                                  p['active'] == true
                                      ? 'Desactivar tipo'
                                      : 'Activar tipo',
                                  [],
                                  explanation: '${p['name']}',
                                );
                                if (v != null) {
                                  await change(
                                    () => repository.setProcedure(
                                      widget.clinic.clinicId,
                                      p['id'] as String,
                                      p['name'] as String,
                                      p['active'] != true,
                                    ),
                                  );
                                }
                              },
                        child: Text(
                          p['active'] == true ? 'Desactivar' : 'Activar',
                        ),
                      ),
                    ),
                ],
                const Divider(),
                const Text('Concesiones'),
                for (final g in rows('grants'))
                  ListTile(
                    title: Text(
                      '${g['code']} · ${procedureName(g['procedure_id'])}',
                    ),
                    subtitle: Text(
                      '${memberName(g['user_id'])}\nVence: ${g['valid_until']}\n${g['revoked'] == true
                          ? 'Revocada'
                          : g['effective'] == true
                          ? 'Requisitos cumplidos'
                          : 'Sin efecto vigente'}',
                    ),
                    trailing: manager && g['revoked'] != true
                        ? TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final v = await edit(
                                      'Revocar permiso',
                                      [('reason', 'Motivo')],
                                      explanation:
                                          '${g['code']} · ${memberName(g['user_id'])}',
                                    );
                                    if (v != null) {
                                      await change(
                                        () => repository.revokePermission(
                                          g['id'] as String,
                                          v['reason']!,
                                        ),
                                      );
                                    }
                                  },
                            child: const Text('Revocar'),
                          )
                        : null,
                  ),
                const Divider(),
                const Text('Responsable de la clínica'),
                for (final d in rows(
                  'responsible',
                ).where((d) => d['revoked_at'] == null))
                  ListTile(
                    title: Text(memberName(d['user_id'])),
                    subtitle: Text(
                      '${d['accepted_at'] == null ? 'Pendiente de aceptación' : 'Aceptado'} · vence ${d['valid_until']}',
                    ),
                    trailing: Wrap(
                      children: [
                        if (d['user_id'] == widget.clinic.userId)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final v = await edit(
                                      d['accepted_at'] == null
                                          ? 'Aceptar responsabilidad'
                                          : 'Dejar responsabilidad',
                                      [],
                                    );
                                    if (v != null) {
                                      await change(
                                        () => repository.respondResponsible(
                                          d['id'] as String,
                                          d['accepted_at'] == null,
                                        ),
                                      );
                                    }
                                  },
                            child: Text(
                              d['accepted_at'] == null ? 'Aceptar' : 'Dejar',
                            ),
                          ),
                        if (manager)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final v = await edit(
                                      'Revocar designación',
                                      [],
                                    );
                                    if (v != null) {
                                      await change(
                                        () => repository.revokeResponsible(
                                          d['id'] as String,
                                        ),
                                      );
                                    }
                                  },
                            child: const Text('Revocar'),
                          ),
                      ],
                    ),
                  ),
                const Divider(),
                const Text('Habilitación profesional'),
                const Text(
                  'El primer MVZ requiere revisión por administración de plataforma fuera de la app. No se acredita por su puesto ni por su rol anterior.',
                ),
                for (final p in rows('profiles', evidence))
                  ListTile(
                    title: Text('${p['name']} · ${p['license']}'),
                    subtitle: const Text(
                      'Datos capturados; la habilitación depende de evidencia vigente.',
                    ),
                    trailing: reviewer && p['user_id'] != widget.clinic.userId
                        ? TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final v = await edit(
                                      'Registrar revisión profesional',
                                      [
                                        (
                                          'reviewed',
                                          'Fecha de revisión (AAAA-MM-DD HH:MM)',
                                        ),
                                        ('hash', 'SHA-256 de evidencia'),
                                        (
                                          'reference',
                                          'Referencia privada de evidencia',
                                        ),
                                        ('until', 'Vence (AAAA-MM-DD HH:MM)'),
                                      ],
                                      explanation:
                                          '${p['name']} · ${p['license']}\nLa revisión solo habilita dentro de esta clínica.',
                                    );
                                    if (v != null) {
                                      await change(
                                        () => repository.reviewProfessional(
                                          widget.clinic.clinicId,
                                          p['version_id'] as String,
                                          DateTime.parse(v['reviewed']!),
                                          v['hash']!,
                                          v['reference']!,
                                          DateTime.parse(v['until']!),
                                        ),
                                      );
                                    }
                                  },
                            child: const Text('Revisar evidencia'),
                          )
                        : null,
                  ),
                for (final v in rows('verifications', evidence))
                  ListTile(
                    title: Text(
                      v['revoked'] == true
                          ? 'Verificación revocada'
                          : 'Verificación registrada',
                    ),
                    subtitle: Text(
                      'Revisor: ${v['reviewer_id']}\nRevisión: ${v['reviewed_at']}\nVence: ${v['valid_until']}\nReferencia: ${v['evidence_reference']}',
                    ),
                    trailing:
                        reviewer &&
                            v['origin'] == 'clinic_responsible' &&
                            v['revoked'] != true
                        ? TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final result = await edit(
                                      'Revocar habilitación',
                                      [('reason', 'Motivo')],
                                    );
                                    if (result != null) {
                                      await change(
                                        () => repository.revokeProfessional(
                                          v['id'] as String,
                                          result['reason']!,
                                        ),
                                      );
                                    }
                                  },
                            child: const Text('Revocar'),
                          )
                        : null,
                  ),
              ],
            ),
    ),
  );
}
