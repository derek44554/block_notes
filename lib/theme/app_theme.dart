import 'package:flutter/material.dart';

class AppPalette {
  AppPalette._();

  static const nightInk = Color(0xFF11151C);
  static const charcoal = Color(0xFF1B212B);
  static const fog = Color(0xFF313946);
  static const paper = Color(0xFFE6D8BF);
  static const sage = Color(0xFF9BAE9A);
  static const plum = Color(0xFF8F7C9F);
  static const copper = Color(0xFFC78B62);
  static const mist = Color(0xFFF3EFE6);
  static const silver = Color(0xFFA4A9B3);

  static const lightBackground = Color(0xFFEFE2CC);
  static const lightSurface = Color(0xFFF3EFE6);
  static const lightSurfaceLow = Color(0xFFE6D8BF);
  static const lightSurfaceHigh = Color(0xFFD8C6AA);
  static const darkSurfaceLow = Color(0xFF151B24);
  static const darkSurfaceHigh = Color(0xFF232C38);

  static Color folder(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? copper : const Color(0xFF9B6648);

  static Color onAccent(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? nightInk : mist;
}

class AppTheme {
  AppTheme._();

  static const _seed = AppPalette.copper;

  static ThemeData light() {
    final cs =
        ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppPalette.copper,
          onPrimary: AppPalette.mist,
          primaryContainer: AppPalette.lightSurfaceLow,
          onPrimaryContainer: AppPalette.nightInk,
          secondary: AppPalette.sage,
          onSecondary: AppPalette.nightInk,
          secondaryContainer: const Color(0xFFD8E2D2),
          onSecondaryContainer: AppPalette.nightInk,
          tertiary: AppPalette.plum,
          onTertiary: AppPalette.mist,
          tertiaryContainer: const Color(0xFFE0D4E5),
          onTertiaryContainer: AppPalette.nightInk,
          surface: AppPalette.lightSurface,
          onSurface: AppPalette.nightInk,
          surfaceContainerLowest: const Color(0xFFFFF7E8),
          surfaceContainerLow: AppPalette.lightSurfaceLow,
          surfaceContainer: const Color(0xFFE0D1B8),
          surfaceContainerHigh: AppPalette.lightSurfaceHigh,
          surfaceContainerHighest: const Color(0xFFCDB99A),
          outline: const Color(0xFF867862),
          outlineVariant: const Color(0xFFB8A78D),
          error: const Color(0xFFA95B45),
          onError: AppPalette.mist,
          errorContainer: const Color(0xFFE9C7BA),
          onErrorContainer: const Color(0xFF3F1D15),
          surfaceTint: AppPalette.copper,
        );
    return _base(cs).copyWith(
      scaffoldBackgroundColor: AppPalette.lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        toolbarHeight: 42,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
    );
  }

  static ThemeData dark() {
    final cs =
        ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppPalette.copper,
          onPrimary: AppPalette.nightInk,
          primaryContainer: const Color(0xFF493326),
          onPrimaryContainer: AppPalette.paper,
          secondary: AppPalette.sage,
          onSecondary: AppPalette.nightInk,
          secondaryContainer: const Color(0xFF2C3A30),
          onSecondaryContainer: const Color(0xFFDDE6D7),
          tertiary: AppPalette.plum,
          onTertiary: AppPalette.mist,
          tertiaryContainer: const Color(0xFF3A3043),
          onTertiaryContainer: const Color(0xFFE7D7EE),
          surface: AppPalette.nightInk,
          onSurface: AppPalette.mist,
          surfaceContainerLowest: const Color(0xFF0C1117),
          surfaceContainerLow: AppPalette.darkSurfaceLow,
          surfaceContainer: AppPalette.charcoal,
          surfaceContainerHigh: AppPalette.darkSurfaceHigh,
          surfaceContainerHighest: AppPalette.fog,
          outline: const Color(0xFF586474),
          outlineVariant: AppPalette.fog,
          error: const Color(0xFFD27B65),
          onError: AppPalette.nightInk,
          errorContainer: const Color(0xFF4D241C),
          onErrorContainer: const Color(0xFFFFD8CF),
          surfaceTint: AppPalette.copper,
        );
    return _base(cs).copyWith(
      scaffoldBackgroundColor: AppPalette.nightInk,
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.nightInk,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        toolbarHeight: 42,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
    );
  }

  static ThemeData _base(ColorScheme cs) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      canvasColor: cs.surface,
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.45),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: cs.primary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        color: cs.surfaceContainerLow,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surfaceTint,
        modalBackgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurfaceVariant,
        textColor: cs.onSurface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
      ),
    );
  }
}
