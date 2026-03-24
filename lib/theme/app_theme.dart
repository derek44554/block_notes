import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFFF5A623); // warm amber for notes

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light);
    return _base(cs).copyWith(
      scaffoldBackgroundColor: const Color(0xFFFAF9F6),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFFAF9F6),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        toolbarHeight: 42,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
    );
  }

  static ThemeData dark() {
    final cs = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark);
    return _base(cs).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF0F0F0F),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        toolbarHeight: 42,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
    );
  }

  static ThemeData _base(ColorScheme cs) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary, width: 2)),
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        color: cs.surfaceContainerLowest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
      ),
    );
  }
}
