import 'package:flutter/material.dart';

abstract final class RelayColors {
  static const canvas = Color(0xFFF8F6F1);
  static const surface = Color(0xFFFFFFFF);
  static const green = Color(0xFF286653);
  static const greenDark = Color(0xFF1E4F41);
  static const greenLight = Color(0xFFE7F0EB);
  static const sage = Color(0xFFA8C7B5);
  static const sageLight = Color(0xFFDFEAE3);
  static const peach = Color(0xFFF2C4A5);
  static const peachLight = Color(0xFFF8E3D3);
  static const coral = Color(0xFFE96D67);
  static const coralLight = Color(0xFFFCE9E7);
  static const text = Color(0xFF1F2937);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE8E5DF);
}

ThemeData buildOfflineRelayTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: RelayColors.green,
    brightness: Brightness.light,
    primary: RelayColors.green,
    onPrimary: RelayColors.surface,
    secondary: RelayColors.sage,
    onSecondary: RelayColors.greenDark,
    surface: RelayColors.surface,
    error: RelayColors.coral,
    onError: RelayColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: RelayColors.canvas,
    fontFamily: 'Inter',
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 36,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: RelayColors.text,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 28,
        height: 1.18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: RelayColors.text,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: RelayColors.text,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: RelayColors.text,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: RelayColors.text),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.55,
        color: RelayColors.muted,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RelayColors.canvas,
      foregroundColor: RelayColors.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: RelayColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RelayColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RelayColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RelayColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RelayColors.green, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        backgroundColor: RelayColors.green,
        foregroundColor: RelayColors.surface,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: RelayColors.green,
        side: const BorderSide(color: RelayColors.border),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    cardTheme: CardThemeData(
      color: RelayColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: RelayColors.border),
      ),
    ),
  );
}
