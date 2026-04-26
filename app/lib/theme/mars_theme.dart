import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Mahfadha Pro — نظام التصميم المريخي الفخم
/// كحلي فضائي داكن + نيون سيان + زجاج لامع (Glassmorphism)
class MarsTheme {
  MarsTheme._();

  // ── الألوان الأساسية ──────────────────────────────────────────────
  static const Color spaceNavy = Color(0xFF0A0E14);
  static const Color deepSpace = Color(0xFF0D1117);
  static const Color surface = Color(0xFF131829);
  static const Color surfaceLight = Color(0xFF1A2235);
  static const Color cardGlass = Color(0x2A1E2A4A);

  // ── ألوان النيون ──────────────────────────────────────────────────
  static const Color cyanNeon = Color(0xFF00FFFF);
  static const Color cyanDim = Color(0xFF2AA5C8);
  static const Color cyanGlow = Color(0xFF63DCFF);
  static const Color accent = Color(0xFF7C5CFC);
  static const Color borderGlow = Color(0x2663DCFF);

  // ── ألوان الحالة ──────────────────────────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color error = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);

  // ── ألوان النص ────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // ── التدرجات ──────────────────────────────────────────────────────
  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF0891B2), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xD40F1728), Color(0xC81E293B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0A0E14), Color(0xFF0F172A), Color(0xFF0A0E14)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const RadialGradient marsRadial = RadialGradient(
    colors: [Color(0xFF1A2235), Color(0xFF0A0E14)],
    radius: 1.5,
  );

  // ── تزيين البطاقة الزجاجية ─────────────────────────────────────────
  static BoxDecoration glassCard({double borderRadius = 20}) {
    return BoxDecoration(
      gradient: cardGradient,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderGlow, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: cyanNeon.withValues(alpha: 0.04),
          blurRadius: 40,
          spreadRadius: -4,
        ),
      ],
    );
  }

  // ── تزيين بوابة الاتصال الزجاجية ──────────────────────────────────
  static BoxDecoration gateGlassCard({double borderRadius = 24}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      boxShadow: [
        BoxShadow(
          color: cyanNeon.withValues(alpha: 0.06),
          blurRadius: 60,
          spreadRadius: -10,
        ),
      ],
    );
  }

  // ── ThemeData ──────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final cairoText = GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme);

    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: spaceNavy,
      primaryColor: cyanNeon,
      colorScheme: const ColorScheme.dark(
        primary: cyanNeon,
        secondary: accent,
        surface: surface,
        error: error,
        onPrimary: Color(0xFF0A0E14),
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      textTheme: cairoText.copyWith(
        displayLarge: GoogleFonts.cairo(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        headlineLarge: GoogleFonts.cairo(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineMedium: GoogleFonts.cairo(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: GoogleFonts.cairo(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: cyanNeon,
        ),
        bodyLarge: GoogleFonts.cairo(
          fontSize: 16,
          color: Colors.white70,
        ),
        bodyMedium: GoogleFonts.cairo(
          color: textSecondary,
          fontSize: 14,
        ),
        labelLarge: GoogleFonts.cairo(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyanNeon,
          foregroundColor: spaceNavy,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.cairo(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cyanNeon,
          side: const BorderSide(color: cyanNeon, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.cairo(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
