import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/module_access.dart';

class ModuleAccessBoundary extends StatefulWidget {
  const ModuleAccessBoundary({
    super.key,
    required this.member,
    required this.repository,
    required this.revision,
    required this.builder,
  });

  final ClinicMembership? member;
  final ModuleAccessRepository? repository;
  final int revision;
  final Widget Function(ModuleAccess? access) builder;

  @override
  State<ModuleAccessBoundary> createState() => _ModuleAccessBoundaryState();
}

class _ModuleAccessBoundaryState extends State<ModuleAccessBoundary> {
  ModuleAccess? access;
  int generation = 0;
  bool failed = false;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant ModuleAccessBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member?.userId != widget.member?.userId ||
        oldWidget.member?.clinicId != widget.member?.clinicId ||
        oldWidget.repository != widget.repository ||
        oldWidget.revision != widget.revision) {
      access = null;
      load();
    }
  }

  Future<void> load() async {
    final request = ++generation;
    final member = widget.member;
    final repository = widget.repository;
    if (member == null || repository == null) return;
    failed = false;
    loading = true;
    try {
      final next = ModuleAccess.read(
        await repository.workspace(member.clinicId),
      );
      if (mounted && request == generation) setState(() {
        access = next;
        loading = false;
      });
    } catch (_) {
      // Fail closed for reviewed modules. A stale contract is never retained.
      if (mounted && request == generation) setState(() {
        access = null;
        failed = true;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(
      widget.member != null && widget.repository != null
          ? access ?? ModuleAccess.denied
          : access,
    );
    if (!failed || widget.member == null || widget.repository == null) {
      return content;
    }
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.errorContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'No se pudieron comprobar los permisos de tu espacio. '
                      'Algunos accesos y resúmenes están ocultos. '
                      'Revisa tu conexión; si persiste, contacta a soporte.',
                    ),
                  ),
                  TextButton(
                    onPressed: loading ? null : () {
                      setState(() => loading = true);
                      load();
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
