import 'neu_identity.dart';
import 'package:flutter/material.dart';

class WorkspaceStyle extends ThemeExtension<WorkspaceStyle> {
  const WorkspaceStyle({required this.neumorphic});
  final bool neumorphic;
  @override
  WorkspaceStyle copyWith({bool? neumorphic}) =>
      WorkspaceStyle(neumorphic: neumorphic ?? this.neumorphic);
  @override
  WorkspaceStyle lerp(covariant WorkspaceStyle? other, double t) =>
      t < .5 ? this : other ?? this;
}

class WorkspacePanel extends StatelessWidget {
  const WorkspacePanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.extension<WorkspaceStyle>()?.neumorphic != true) {
      return Card(child: child);
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: neuShadows(theme.brightness == Brightness.dark),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

IconData sectionIcon(String page) => switch (page) {
  'Inicio' => Icons.dashboard_outlined,
  'Cálculos' ||
  'Cálculo rápido' ||
  'Vademécum' ||
  'Operaciones de dosis' => Icons.calculate_outlined,
  'Cálculos clínicos' => Icons.science_outlined,
  'Escanear producto' => Icons.qr_code_scanner,
  'Hospitalización' => Icons.local_hospital_outlined,
  'Pacientes' => Icons.pets_outlined,
  'Formatos' => Icons.folder_outlined,
  'Receta' || 'Recetas' => Icons.description_outlined,
  'Agenda' => Icons.calendar_month_outlined,
  'Checado' => Icons.badge_outlined,
  'Asistente IA' => Icons.auto_awesome,
  'Planes' => Icons.workspace_premium_outlined,
  'Producto y costos' => Icons.info_outline,
  'Inicio guiado' => Icons.explore_outlined,
  'Ayuda y soporte' => Icons.help_outline,
  'Estadísticas' => Icons.bar_chart_outlined,
  'Respaldo' || 'Estadísticas y respaldo' => Icons.backup_outlined,
  'Planeación financiera' => Icons.trending_up,
  'Caja' => Icons.point_of_sale_outlined,
  'Equipo y avisos' || 'Pendientes del equipo' => Icons.forum_outlined,
  'Inventario' => Icons.inventory_2_outlined,
  'Ajustes' => Icons.tune,
  _ => Icons.apps_outlined,
};
