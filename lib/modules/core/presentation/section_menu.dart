import 'package:flutter/material.dart';
import '../../../core/widgets/workspace_panel.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/module_access.dart';
import '../domain/navigation_access.dart';
import '../domain/section_catalog.dart';

class SectionMenu extends StatefulWidget {
  const SectionMenu({
    super.key,
    required this.onNavigate,
    this.member,
    this.access,
    this.onAccount,
    this.initialGroup,
  });
  final ValueChanged<String> onNavigate;
  final ClinicMembership? member;
  final ModuleAccess? access;
  final VoidCallback? onAccount;
  final String? initialGroup;
  @override
  State<SectionMenu> createState() => _SectionMenuState();
}

class _SectionMenuState extends State<SectionMenu> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = <SectionGroup>[];
    for (final group in sectionGroups) {
      final authorized = group.pages
          .where(
            (page) =>
                (page != 'Mi cuenta y clínicas' || widget.onAccount != null) &&
                navigationAllowed(page, widget.member, widget.access),
          )
          .toList();
      if (authorized.isEmpty) continue;
      bool matches(String page) =>
          normalizeSection(page).contains(query) ||
          normalizeSection(group.title).contains(query);
      final pages = authorized.where(matches).toList();
      final planned = group.planned.where(matches).toList();
      if (pages.isNotEmpty || planned.isNotEmpty) {
        filtered.add(SectionGroup(group.title, pages, planned: planned));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Secciones', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Herramientas y gestión de tu espacio.'),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar secciones',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => query = normalizeSection(value)),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Text('No hay secciones disponibles para esa búsqueda.'),
        for (final group in filtered)
          ExpansionTile(
            key: ValueKey((group.title, query, widget.initialGroup)),
            title: Text(group.title),
            initiallyExpanded:
                query.isNotEmpty || widget.initialGroup == group.title,
            children: [
              for (final page in group.planned)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(page),
                  subtitle: const Text('En preparación'),
                  enabled: false,
                ),
              for (final page in group.pages)
                ListTile(
                  leading: Icon(sectionIcon(page)),
                  title: Text(page),
                  onTap: page == 'Mi cuenta y clínicas'
                      ? widget.onAccount
                      : () => widget.onNavigate(page),
                ),
            ],
          ),
      ],
    );
  }
}

class CalculationMenu extends StatelessWidget {
  const CalculationMenu({
    super.key,
    required this.onNavigate,
    this.member,
    this.access,
  });
  final ValueChanged<String> onNavigate;
  final ClinicMembership? member;
  final ModuleAccess? access;
  @override
  Widget build(BuildContext context) {
    final canDose = navigationAllowed('Cálculo rápido', member, access);
    final canClinical = navigationAllowed('Cálculos clínicos', member, access);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Calculadoras', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Elige la operación que necesitas.'),
        const SizedBox(height: 12),
        if (canDose)
          _CalculationChoice(
            icon: Icons.medication_outlined,
            title: 'Calcular dosis de un producto',
            description:
                'Usa un catálogo con fuente y concentración por presentación; requiere revisión y confirmación.',
            onTap: () => onNavigate('Cálculo rápido'),
          ),
        if (canDose)
          _CalculationChoice(
            icon: Icons.calculate_outlined,
            title: 'Otras operaciones de dosis',
            description:
                'Regla de tres, concentración tras reconstitución, UI y conversión métrica con parámetros explícitos.',
            onTap: () => onNavigate('Operaciones de dosis'),
          ),
        if (canClinical)
          _CalculationChoice(
            icon: Icons.monitor_heart_outlined,
            title: 'Cálculos clínicos',
            description:
                'Fluidos, constantes, protocolos, peso metabólico, retiros y otras herramientas disponibles.',
            onTap: () => onNavigate('Cálculos clínicos'),
          ),
      ],
    );
  }
}

class _CalculationChoice extends StatelessWidget {
  const _CalculationChoice({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final IconData icon;
  final String title, description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(description),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
