import 'package:flutter/material.dart';

import 'vet_theme.dart';

enum VetActionStyle { primary, secondary, neutral, destructive }

enum VetBadgeKind { information, success, warning, danger, unverified }

class VetCard extends StatelessWidget {
  const VetCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: dark ? Colors.black26 : VetColors.softShadow,
            offset: const Offset(3, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class VetActionButton extends StatelessWidget {
  const VetActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = VetActionStyle.primary,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final VetActionStyle style;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (style) {
      VetActionStyle.primary => (colors.primary, colors.onPrimary),
      VetActionStyle.secondary => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      VetActionStyle.neutral => (colors.surfaceContainerLow, colors.onSurface),
      VetActionStyle.destructive => (colors.error, colors.onError),
    };
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          if (icon != null || loading) const SizedBox(width: 8),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class VetStatusBadge extends StatelessWidget {
  const VetStatusBadge({
    super.key,
    required this.label,
    this.kind = VetBadgeKind.information,
  });
  final String label;
  final VetBadgeKind kind;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (kind) {
      VetBadgeKind.information => Theme.of(context).colorScheme.primary,
      VetBadgeKind.success =>
        dark ? const Color(0xFF7DE1B8) : VetColors.success,
      VetBadgeKind.warning =>
        dark ? const Color(0xFFFFD580) : VetColors.warning,
      VetBadgeKind.danger => Theme.of(context).colorScheme.error,
      VetBadgeKind.unverified => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class VetModuleTile extends StatelessWidget {
  const VetModuleTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.accent = VetColors.turquoise,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => VetCard(
    padding: EdgeInsets.zero,
    radius: 20,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 112),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class VetPracticeSelector extends StatelessWidget {
  const VetPracticeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final int selected;
  final ValueChanged<int> onChanged;
  static const labels = ['Pequeñas especies', 'Exóticos', 'Producción'];
  static const icons = [
    Icons.pets_outlined,
    Icons.cruelty_free_outlined,
    Icons.agriculture_outlined,
  ];
  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(3, (i) {
      final active = i == selected;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
          child: Semantics(
            selected: active,
            button: true,
            label: labels[i],
            child: Material(
              color: active
                  ? VetColors.lavender.withValues(alpha: .22)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onChanged(i),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 84),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: active ? VetColors.purple : VetColors.softShadow,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icons[i],
                        color: active ? VetColors.purple : VetColors.turquoise,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }),
  );
}

class VetKpiCard extends StatelessWidget {
  const VetKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = VetColors.purple,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) => VetCard(
    radius: 16,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    child: Column(
      children: [
        Icon(icon, color: accent, size: 24),
        const SizedBox(height: 7),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
