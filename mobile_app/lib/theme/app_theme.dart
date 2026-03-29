import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 80s Medieval Dark Theme — Castlevania × Vlad Țepeș
class AppTheme {
  // ── Palette ──────────────────────────────────────────────────────────────────
  static const Color neonCyan   = Color(0xFFD4A017); // tarnished gold (main accent)
  static const Color neonPink   = Color(0xFFCC1A1A); // battle crimson
  static const Color neonPurple = Color(0xFF7B1FA2); // arcane purple
  static const Color neonGreen  = Color(0xFF00C853); // emerald torch
  static const Color neonYellow = Color(0xFFFFD700); // bright gold
  static const Color neonOrange = Color(0xFFFF8C00); // torch amber
  static const Color neonRed    = Color(0xFFCC0000); // blood red

  static const Color darkBg          = Color(0xFF0A0000); // blood-black void
  static const Color darkBgSecondary = Color(0xFF180808); // dungeon stone
  static const Color darkBgTertiary  = Color(0xFF261010); // dark alcove

  static const Color parchment = Color(0xFFDEC5A0); // old scroll
  static const Color gold      = Color(0xFFD4A017);
  static const Color goldBright= Color(0xFFFFD700);
  static const Color crimson   = Color(0xFF8B0000);
  static const Color silver    = Color(0xFFB0B0B0);

  // ── Team colors (medieval heraldry) ──────────────────────────────────────────
  static const Map<String, Color> teamColors = {
    'red':    Color(0xFFCC0000), // Valahia — red
    'blue':   Color(0xFF1565C0), // Ardeal — royal blue
    'green':  Color(0xFF2E7D32), // Moldova — forest green
    'purple': Color(0xFF6A1B9A), // Arcane — dark purple
  };

  // ── Google Font helpers ───────────────────────────────────────────────────────
  static TextStyle cinzel({
    double fontSize = 16,
    FontWeight weight = FontWeight.bold,
    Color color = parchment,
    double letterSpacing = 2,
    List<Shadow>? shadows,
  }) =>
      GoogleFonts.cinzel(
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        shadows: shadows,
      );

  // ── Theme ─────────────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: darkBg,
      primaryColor: gold,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFD4A017),
        secondary: Color(0xFFCC1A1A),
        tertiary: Color(0xFF7B1FA2),
        surface: Color(0xFF180808),
        background: Color(0xFF0A0000),
        error: Color(0xFFCC0000),
      ),
      textTheme: GoogleFonts.cinzelTextTheme(base.textTheme).copyWith(
        displayLarge: cinzel(fontSize: 32, letterSpacing: 3,
            shadows: [Shadow(color: gold.withOpacity(0.8), blurRadius: 16)]),
        displayMedium: cinzel(fontSize: 24, letterSpacing: 2.5,
            shadows: [Shadow(color: gold.withOpacity(0.6), blurRadius: 12)]),
        titleLarge: cinzel(fontSize: 20, letterSpacing: 2,
            shadows: [Shadow(color: gold.withOpacity(0.5), blurRadius: 8)]),
        titleMedium: cinzel(fontSize: 16, letterSpacing: 1.5),
        bodyLarge: GoogleFonts.cinzel(fontSize: 15, color: parchment.withOpacity(0.85)),
        bodyMedium: GoogleFonts.cinzel(fontSize: 13, color: parchment.withOpacity(0.7)),
        labelLarge: cinzel(fontSize: 13, letterSpacing: 2, color: goldBright),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: crimson.withOpacity(0.35),
          foregroundColor: goldBright,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          textStyle: cinzel(fontSize: 13, letterSpacing: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: gold.withOpacity(0.8), width: 1.5),
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFD4A017), size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: cinzel(fontSize: 18, letterSpacing: 3,
            shadows: [Shadow(color: gold.withOpacity(0.9), blurRadius: 14)]),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkBgTertiary,
        contentTextStyle: cinzel(fontSize: 13, color: parchment, letterSpacing: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: gold.withOpacity(0.6)),
        ),
      ),
    );
  }

  // ── Box decoration (replaces neonBoxDecoration) ───────────────────────────────
  static BoxDecoration neonBoxDecoration({
    Color color = gold,
    double borderRadius = 4,
    double glowIntensity = 0.5,
  }) {
    return BoxDecoration(
      color: darkBgSecondary,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: color.withOpacity(0.75), width: 1.5),
      boxShadow: [
        BoxShadow(color: color.withOpacity(glowIntensity * 0.4), blurRadius: 12, spreadRadius: 1),
        BoxShadow(color: crimson.withOpacity(0.15), blurRadius: 24, spreadRadius: 2),
      ],
    );
  }

  // ── Text style with glow (keeps neonTextStyle name for compatibility) ─────────
  static TextStyle neonTextStyle({
    Color color = gold,
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.bold,
  }) =>
      cinzel(
        color: color,
        fontSize: fontSize,
        weight: fontWeight,
        letterSpacing: 2,
        shadows: [
          Shadow(color: color.withOpacity(0.85), blurRadius: 12),
          Shadow(color: color.withOpacity(0.4), blurRadius: 24),
        ],
      );

  // ── Decorative divider string ─────────────────────────────────────────────────
  static const String divider = '⸻ ✦ ⸻';

  // ── Shield/panel decoration ───────────────────────────────────────────────────
  static BoxDecoration panelDecoration({Color? borderColor}) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [darkBgTertiary, darkBgSecondary],
    ),
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: (borderColor ?? gold).withOpacity(0.7), width: 1.5),
    boxShadow: [
      BoxShadow(color: (borderColor ?? gold).withOpacity(0.2), blurRadius: 16),
      BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 8, offset: const Offset(2, 4)),
    ],
  );
}
