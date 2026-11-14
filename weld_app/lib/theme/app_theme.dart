import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ═══════════════════════════════════════════════════════════════
/// Premium Industrial AI Design System
/// Inspired by iWDI (IIT Kharagpur), Tesla Factory UI, NVIDIA Omniverse
/// ═══════════════════════════════════════════════════════════════

// ─── COLORS ──────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Base Navy Dark Surfaces
  static const Color bgBase = Color(0xFF0A1120);
  static const Color bgPanel = Color(0xFF141C2F);
  static const Color bgElevated = Color(0xFF1B2740);
  static const Color border = Color(0xFF223049);
  static const Color borderBright = Color(0xFF2A3B57);

  // Signature Accents
  static const Color arc = Color(0xFFFF5A1F); // Welding orange
  static const Color arcGlow = Color(0x66FF5A1F);
  static const Color scan = Color(0xFF2F9BFF); // Primary action blue
  static const Color scanGlow = Color(0x662F9BFF);
  static const Color neonBlue = Color(0xFF2F9BFF);

  // Status
  static const Color pass = Color(0xFF22C55E);
  static const Color fail = Color(0xFFFF5A5F);
  static const Color caution = Color(0xFFFBBF24);

  // Glass & Highlights
  static const Color glassWhite = Color(0x14FFFFFF);
  static const Color textPrimary = Color(0xFFF3F6FB);
  static const Color textSecondary = Color(0xFF8FA1BD);
  static const Color textMuted = Color(0xFF56698A);
}

// ─── TYPOGRAPHY ──────────────────────────────────────────────────

class AppText {
  AppText._();

  static const String orbitron = 'Orbitron';
  static const String rajdhani = 'Rajdhani';
  static const String inter = 'Inter';

  static TextStyle display({double size = 28, Color color = AppColors.textPrimary}) {
    return GoogleFonts.rajdhani(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.8,
      height: 1.1,
      color: color,
    );
  }

  static TextStyle eyebrow({Color color = AppColors.textSecondary}) {
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.2,
      color: color,
    );
  }

  static TextStyle body({
    double size = 15,
    Color color = AppColors.textSecondary,
    FontWeight weight = FontWeight.w400,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.5,
    );
  }

  static TextStyle data({
    double size = 15,
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w700,
  }) {
    return GoogleFonts.orbitron(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: 0.5,
    );
  }
}

// ─── DECORATIONS ─────────────────────────────────────────────────

class AppDecor {
  AppDecor._();

  /// Full-screen radial gradient background
  static const BoxDecoration shopFloor = BoxDecoration(
    gradient: RadialGradient(
      center: Alignment.topCenter,
      radius: 1.25,
      colors: [
        Color(0xFF122040),
        AppColors.bgBase,
      ],
    ),
  );

  /// Default panel
  static BoxDecoration panel({
    Color? accent,
    double radius = 18,
  }) {
    return BoxDecoration(
      color: AppColors.bgPanel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accent ?? AppColors.border,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .35),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  /// Glass card
  static BoxDecoration glassCard({
    Color? borderColor,
    double radius = 20,
  }) {
    return BoxDecoration(
      color: AppColors.glassWhite,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ??
            AppColors.borderBright.withValues(alpha: .45),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .45),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  /// Elevated card
  static BoxDecoration elevated({
    Color? accent,
    double radius = 20,
  }) {
    return BoxDecoration(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accent ?? AppColors.borderBright,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .40),
          blurRadius: 30,
          offset: const Offset(0, 16),
        ),
      ],
    );
  }

  /// Gradient card
  static BoxDecoration gradientCard({
    Color start = AppColors.bgElevated,
    Color end = AppColors.bgPanel,
    double radius = 20,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border),
    );
  }

  /// Orange glow
  static List<BoxShadow> arcGlow({double blur = 18}) {
    return [
      BoxShadow(
        color: AppColors.arc.withValues(alpha: .30),
        blurRadius: blur,
        spreadRadius: 1,
      ),
      BoxShadow(
        color: AppColors.arc.withValues(alpha: .15),
        blurRadius: blur * 2,
        spreadRadius: 2,
      ),
    ];
  }

  /// Cyan glow
  static List<BoxShadow> scanGlow({double blur = 18}) {
    return [
      BoxShadow(
        color: AppColors.scan.withValues(alpha: .30),
        blurRadius: blur,
        spreadRadius: 1,
      ),
      BoxShadow(
        color: AppColors.scan.withValues(alpha: .15),
        blurRadius: blur * 2,
        spreadRadius: 2,
      ),
    ];
  }

  /// Custom glow
  static List<BoxShadow> neonGlow(Color color, {double blur = 18}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: .35),
        blurRadius: blur,
        spreadRadius: 1,
      ),
      BoxShadow(
        color: color.withValues(alpha: .18),
        blurRadius: blur * 2,
        spreadRadius: 2,
      ),
    ];
  }
}

// ─── COMPLETE THEME ──────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // ── Scaffold ──
      scaffoldBackgroundColor: AppColors.bgBase,

      // ── Color Scheme ──
      colorScheme: const ColorScheme.dark(
        primary: AppColors.scan,
        onPrimary: Colors.white,
        secondary: AppColors.arc,
        onSecondary: Colors.white,
        surface: AppColors.bgPanel,
        onSurface: AppColors.textPrimary,
        error: AppColors.fail,
        onError: Colors.white,
      ),

      // ── Text Theme ──
      textTheme: TextTheme(
        displayLarge: AppText.display(size: 32),
        displayMedium: AppText.display(size: 28),
        displaySmall: AppText.display(size: 24),
        headlineLarge: AppText.display(size: 22),
        headlineMedium: AppText.display(size: 20),
        headlineSmall: AppText.display(size: 18),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: AppText.body(size: 16),
        bodyMedium: AppText.body(size: 14),
        bodySmall: AppText.body(size: 12),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
        labelMedium: AppText.eyebrow(),
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 24),
        titleTextStyle: AppText.display(size: 20),
      ),

      // ── Input Fields ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgPanel,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        labelStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.scan, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.fail),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.fail, width: 2),
        ),
        errorStyle: GoogleFonts.inter(
          color: AppColors.fail,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Elevated Buttons ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.scan,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.bgElevated,
          disabledForegroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 6,
          shadowColor: AppColors.scanGlow,
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // ── Text Buttons ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.scan,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // ── Outlined Buttons ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.scan,
          side: const BorderSide(color: AppColors.scan, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        color: AppColors.bgPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Dialogs ──
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgPanel,
        elevation: 24,
        shadowColor: Colors.black87,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: AppText.display(size: 18),
        contentTextStyle: AppText.body(size: 14),
      ),

      // ── SnackBars ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgElevated,
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      // ── Bottom Nav Bar ──
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgPanel,
        selectedItemColor: AppColors.arc,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ── Floating Action Button ──
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.scan,
        foregroundColor: Colors.white,
        elevation: 8,
      ),

      // ── Icon ──
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 24,
      ),

      // ── ProgressIndicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.scan,
        linearTrackColor: AppColors.bgElevated,
        circularTrackColor: AppColors.bgElevated,
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 12,
        ),
      ),
    );
  }
}