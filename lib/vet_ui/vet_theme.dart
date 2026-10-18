import 'package:flutter/material.dart';

/// Identidad cromática consolidada de los HTML de Stitch. Sin dependencias web.
abstract final class VetColors {
  static const canvas = Color(0xFFF1F4F8);
  static const surface = Color(0xFFF7F9FC);
  static const raised = Color(0xFFFFFFFF);
  static const recessed = Color(0xFFEDF2F7);
  static const softShadow = Color(0xFFDDE4EE);
  static const ink = Color(0xFF0B1C30);
  static const muted = Color(0xFF64748B);
  static const turquoise = Color(0xFF28D7D1);
  static const cyan = Color(0xFF49DFF0);
  static const mint = Color(0xFF61E2D0);
  static const lavender = Color(0xFFC8B5F6);
  static const lilac = Color(0xFFAE92F3);
  static const violet = Color(0xFF7D7AF2);
  static const purple = Color(0xFF7C4DFF);
  static const purpleDeep = Color(0xFF632CE5);
  static const pink = Color(0xFFFF4FB3);
  // Semánticos: NO usar el rosa decorativo como alerta médica por defecto.
  static const danger = Color(0xFFB42318);
  static const warning = Color(0xFF9A6700);
  static const success = Color(0xFF087F5B);
}

abstract final class VetTheme {
  static ThemeData light() {
    final colors =
        ColorScheme.fromSeed(
          seedColor: VetColors.purple,
          brightness: Brightness.light,
          surface: VetColors.surface,
        ).copyWith(
          primary: VetColors.purple,
          onPrimary: Colors.white,
          secondary: VetColors.turquoise,
          onSecondary: VetColors.ink,
          error: VetColors.danger,
          surface: VetColors.surface,
          onSurface: VetColors.ink,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: VetColors.canvas,
      fontFamily:
          null, // Cargar Plus Jakarta Sans como recurso local si se dispone de ella.
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: VetColors.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: VetColors.ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: VetColors.ink),
        bodyMedium: TextStyle(fontSize: 14, color: VetColors.ink),
        bodySmall: TextStyle(fontSize: 12, color: VetColors.muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VetColors.recessed,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: VetColors.softShadow),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: VetColors.softShadow),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: VetColors.purple, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: VetColors.raised,
        indicatorColor: VetColors.lavender.withValues(alpha: .35),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
