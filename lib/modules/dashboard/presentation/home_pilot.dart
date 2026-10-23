import 'package:flutter/material.dart';
import '../../../core/widgets/workspace_panel.dart';
import '../../../core/widgets/neu_identity.dart';
import '../../../vet_ui/vet_theme.dart';
import '../../core/presentation/core_view_model.dart';

/// Shared shell presentation. It never changes membership or access.
ThemeData homePilotTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  // The functional home shell must preserve the selected Neu palette.
  if (base.extension<WorkspaceStyle>()?.neumorphic == true) {
    return base.copyWith(
      drawerTheme: base.drawerTheme.copyWith(
        backgroundColor: base.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: base.colorScheme.surface,
        indicatorColor: base.colorScheme.primary.withValues(
          alpha: dark ? 0.22 : 0.18,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: base.scaffoldBackgroundColor,
        foregroundColor: base.colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
  final surface = dark ? const Color(0xFF131E2A) : VetColors.surface;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: VetColors.purple,
        brightness: base.brightness,
        surface: surface,
      ).copyWith(
        primary: dark ? VetColors.lavender : VetColors.purpleDeep,
        onPrimary: dark ? VetColors.ink : Colors.white,
        secondary: dark ? VetColors.mint : const Color(0xFF087F7C),
        secondaryContainer: dark
            ? const Color(0xFF144541)
            : const Color(0xFFD8F7F3),
        onSecondaryContainer: dark ? VetColors.mint : VetColors.ink,
        onSurface: dark ? const Color(0xFFE3ECF2) : VetColors.ink,
      );
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0B121C) : VetColors.canvas,
    colorScheme: scheme,
    drawerTheme: base.drawerTheme.copyWith(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: surface,
      indicatorColor: scheme.secondaryContainer,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    extensions: [
      ...base.extensions.values.where((e) => e is! WorkspaceStyle),
      const WorkspaceStyle(neumorphic: true),
    ],
  );
}

class HomeSurface extends StatelessWidget {
  const HomeSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.selected = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: .08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: .5),
        ),
        boxShadow: theme.extension<WorkspaceStyle>()?.neumorphic == true
            ? neuShadows(dark)
            : [
                BoxShadow(
                  color: dark ? Colors.black26 : const Color(0xFFDDE4EE),
                  offset: const Offset(5, 6),
                  blurRadius: 14,
                ),
                BoxShadow(
                  color: dark ? const Color(0xFF1C2935) : Colors.white,
                  offset: const Offset(-4, -4),
                  blurRadius: 12,
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class HomePracticeSelector extends StatelessWidget {
  const HomePracticeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final ClinicalBranch selected;
  final ValueChanged<ClinicalBranch> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Selecciona tu tipo de práctica',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
          final columns = largeText || constraints.maxWidth < 280 ? 1 : 3;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final branch in ClinicalBranch.values.where(
                (b) => b != ClinicalBranch.management,
              ))
                SizedBox(
                  width: (constraints.maxWidth - 12 * (columns - 1)) / columns,
                  child: Semantics(
                    selected: branch == selected,
                    button: true,
                    child: HomeSurface(
                      padding: EdgeInsets.zero,
                      selected: branch == selected,
                      child: InkWell(
                        onTap: () => onChanged(branch),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 18,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 80),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  branch.icon,
                                  color: branch == selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  switch (branch) {
                                    ClinicalBranch.small => 'Pequeñas especies',
                                    ClinicalBranch.exotic => 'Exóticos',
                                    _ => 'Producción y grandes especies',
                                  },
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => onChanged(ClinicalBranch.management),
          icon: Icon(
            selected == ClinicalBranch.management
                ? Icons.check_circle_outline
                : Icons.business_outlined,
          ),
          label: const Text('Gestión clínica'),
        ),
      ),
    ],
  );
}

class HomeModuleGrid extends StatelessWidget {
  const HomeModuleGrid({
    super.key,
    required this.actions,
    required this.onNavigate,
  });
  final List<(String, String)> actions;
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = constraints.maxWidth >= 320 && scale < 1.4
          ? 3
          : constraints.maxWidth >= 260 && scale < 1.8
          ? 2
          : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          for (var i = 0; i < actions.length; i++)
            SizedBox(
              width: (constraints.maxWidth - 12 * (columns - 1)) / columns,
              child: HomeSurface(
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: () => onNavigate(actions[i].$2),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 124),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: VetColors.lavender.withValues(alpha: .24),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              sectionIcon(actions[i].$2),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            actions[i].$1,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontSize: 12, letterSpacing: 0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class HomeSummary extends StatelessWidget {
  const HomeSummary({super.key, required this.metrics, this.activity});
  final List<(String, String, IconData)> metrics;
  final List<(String, int)>? activity;
  @override
  Widget build(BuildContext context) => HomeSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tu espacio en cifras',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        const Text('Datos consultados · según tus permisos'),
        const SizedBox(height: 16),
        if (metrics.isEmpty)
          const Text('Elige un espacio con acceso para consultar su resumen.'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 380 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.25
                ? 4
                : constraints.maxWidth >= 240 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.6
                ? 2
                : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width:
                        (constraints.maxWidth - 12 * (columns - 1)) / columns,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .05),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            metric.$3,
                            color: Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            metric.$2,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            metric.$1,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(letterSpacing: 0),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (activity != null) ...[
          const SizedBox(height: 20),
          const Text('Citas consultadas · últimos 7 días'),
          const SizedBox(height: 12),
          if (activity!.every((day) => day.$2 == 0))
            const Text('Sin citas en los datos consultados de este periodo.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (MediaQuery.textScalerOf(context).scale(1) > 1.5) {
                  return Wrap(
                    spacing: 12,
                    children: [
                      for (final day in activity!) Text('${day.$1}: ${day.$2}'),
                    ],
                  );
                }
                final max = activity!
                    .map((e) => e.$2)
                    .reduce((a, b) => a > b ? a : b);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in activity!)
                      Expanded(
                        child: Semantics(
                          label: '${day.$1}: ${day.$2} citas',
                          child: ExcludeSemantics(
                            child: Column(
                              children: [
                                Text(
                                  '${day.$2}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: 12,
                                  height: day.$2 == 0
                                      ? 2
                                      : 12 + 60 * day.$2 / max,
                                  decoration: BoxDecoration(
                                    color: day.$2 == 0
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant
                                        : Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  day.$1,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ],
    ),
  );
}
