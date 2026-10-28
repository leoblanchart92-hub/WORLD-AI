import 'package:flutter/material.dart';

/// Palette et thème de WORLD-AI : sombre, violet profond, accents cyan.
///
/// Les couleurs sont déclarées explicitement (plutôt que dérivées du
/// [ColorScheme]) pour que les cartes gardent le même rendu quelle que soit la
/// version de Flutter utilisée pour compiler l'APK.
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF8B6CFF);
  static const Color accent = Color(0xFF3FD9C6);
  static const Color success = Color(0xFF4CD9A4);
  static const Color background = Color(0xFF08060F);
  static const Color surface = Color(0xFF14101F);
  static const Color surfaceHigh = Color(0xFF1D1730);
  static const Color outline = Color(0xFF2C2444);
  static const Color text = Color(0xFFEDEAF7);
  static const Color textSoft = Color(0xFFC9C2E4);
  static const Color muted = Color(0xFF9A93B5);

  /// Dégradé des cartes d'en-tête.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6E4BFF), Color(0xFF3B2394), Color(0xFF17102E)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Dégradé des pastilles et boutons d'accent.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, Color(0xFF4FA8FF)],
  );

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: seed,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: const Color(0xFF04231F),
      surface: surface,
      onSurface: text,
      error: const Color(0xFFFF6B81),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      navigationDrawerTheme: const NavigationDrawerThemeData(
        backgroundColor: Color(0xFF0F0C1B),
        surfaceTintColor: Colors.transparent,
        indicatorColor: Color(0x338B6CFF),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF2A2340),
          disabledForegroundColor: muted,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textSoft,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: textSoft),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: text, fontSize: 13),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surfaceHigh,
        circularTrackColor: surfaceHigh,
      ),
      listTileTheme: const ListTileThemeData(iconColor: textSoft),
    );
  }
}
