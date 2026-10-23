import 'package:flutter/material.dart';
import 'neu_identity.dart';
import 'workspace_panel.dart';

/// Stable identities shared by the tool selector and its calculation surface.
({Color color, IconData icon}) calculatorIdentity(String id) => switch (id) {
  'dose' => (color: const Color(0xFF087F70), icon: Icons.medication_outlined),
  'fluids' => (color: const Color(0xFF087B91), icon: Icons.water_drop_outlined),
  'cri' => (color: const Color(0xFF7550AE), icon: Icons.speed_outlined),
  'herd' => (color: const Color(0xFF555CB0), icon: Icons.pets_outlined),
  'water' => (color: const Color(0xFF087E82), icon: Icons.water_outlined),
  'feed' => (color: const Color(0xFF94619B), icon: Icons.grass_outlined),
  'adjustment' => (color: const Color(0xFF9A36AE), icon: Icons.tune),
  'vitals' => (
    color: const Color(0xFF087E82),
    icon: Icons.monitor_heart_outlined,
  ),
  'metabolic' => (
    color: const Color(0xFF555CB0),
    icon: Icons.monitor_weight_outlined,
  ),
  'protocols' => (color: const Color(0xFF7550AE), icon: Icons.checklist),
  _ => (color: const Color(0xFF7550AE), icon: Icons.schedule),
};

class CalculatorIcon extends StatelessWidget {
  const CalculatorIcon(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context) {
    final identity = calculatorIdentity(id);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark
        ? Color.lerp(identity.color, Colors.white, .5)!
        : identity.color;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(identity.icon, color: color, size: 24),
    );
  }
}

class CalculatorSurface extends StatelessWidget {
  const CalculatorSurface({super.key, required this.id, required this.child});
  final String id;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final neu = base.extension<WorkspaceStyle>()?.neumorphic == true;
    final identity = calculatorIdentity(id);
    final accent = dark
        ? Color.lerp(identity.color, Colors.white, .5)!
        : identity.color;
    final surface = Color.lerp(
      base.scaffoldBackgroundColor,
      identity.color,
      dark ? .12 : .07,
    )!;
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: surface,
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: surface,
          border: neu ? NeuInputBorder(dark: dark) : null,
          enabledBorder: neu ? NeuInputBorder(dark: dark) : null,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: dark ? const Color(0xFF101A28) : Colors.white,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: neu ? neuShadows(dark) : null,
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
