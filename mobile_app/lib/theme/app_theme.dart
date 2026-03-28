import 'package:flutter/material.dart';

class AppTheme {
  // Cyberpunk Neon Colors
  static const Color neonCyan = Color(0xFF00D4FF);
  static const Color neonPink = Color(0xFFFF0080);
  static const Color neonPurple = Color(0xFF9D00FF);
  static const Color neonGreen = Color(0xFF00FF88);
  static const Color neonYellow = Color(0xFFFFE500);
  static const Color neonOrange = Color(0xFFFF6B00);
  static const Color neonRed = Color(0xFFFF0040);
  
  // Background colors
  static const Color darkBg = Color(0xFF0A0A0F);
  static const Color darkBgSecondary = Color(0xFF12121A);
  static const Color darkBgTertiary = Color(0xFF1A1A25);
  
  // Team colors
  static const Map<String, Color> teamColors = {
    'red': neonRed,
    'blue': neonCyan,
    'green': neonGreen,
    'purple': neonPurple,
  };
  
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: neonCyan,
      colorScheme: const ColorScheme.dark(
        primary: neonCyan,
        secondary: neonPink,
        tertiary: neonPurple,
        surface: darkBgSecondary,
        background: darkBg,
        error: neonRed,
      ),
      fontFamily: null,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 2,
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 1.5,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 1,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Colors.white70,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Colors.white70,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 1,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonCyan.withOpacity(0.2),
          foregroundColor: neonCyan,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: neonCyan, width: 1),
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: neonCyan,
        size: 24,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: neonCyan,
          letterSpacing: 2,
        ),
      ),
    );
  }
  
  // Neon glow box decoration
  static BoxDecoration neonBoxDecoration({
    Color color = neonCyan,
    double borderRadius = 12,
    double glowIntensity = 0.5,
  }) {
    return BoxDecoration(
      color: darkBgSecondary,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: color.withOpacity(0.8), width: 1),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(glowIntensity * 0.5),
          blurRadius: 10,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: color.withOpacity(glowIntensity * 0.3),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    );
  }
  
  // Neon text style
  static TextStyle neonTextStyle({
    Color color = neonCyan,
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.bold,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: 1,
      shadows: [
        Shadow(
          color: color.withOpacity(0.8),
          blurRadius: 10,
        ),
        Shadow(
          color: color.withOpacity(0.5),
          blurRadius: 20,
        ),
      ],
    );
  }
}
