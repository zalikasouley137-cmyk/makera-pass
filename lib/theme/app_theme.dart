import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Fond et surfaces sombres épurées
  static const Color bgDark = Color(0xFF070B14);
  static const Color surfaceCard = Color(0xFF0F172A);
  static const Color surfaceCardLight = Color(0xFF1E293B);
  static const Color surfaceElevated = Color(0xFF182234);

  // Bordures et séparateurs
  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color borderLight = Color(0x2EFFFFFF);
  static const Color borderFocus = Color(0xFFF28123);

  // Accents d'action
  static const Color primaryOrange = Color(0xFFF28123);
  static const Color primaryOrangeLight = Color(0xFFFF9E47);
  static const Color primaryOrangeDark = Color(0xFFD66A12);

  static const Color accentBlue = Color(0xFF0284C7);
  static const Color accentBlueLight = Color(0xFF38BDF8);

  static const Color accentPurple = Color(0xFFA855F7);
  static const Color accentPurpleLight = Color(0xFFC084FC);

  static const Color successGreen = Color(0xFF10B981);
  static const Color successGreenLight = Color(0xFF34D399);

  static const Color dangerRed = Color(0xFFEF4444);
  static const Color dangerRedLight = Color(0xFFF87171);

  static const Color warningAmber = Color(0xFFF59E0B);

  // Textes
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF); // 70%
  static const Color textMuted = Color(0x73FFFFFF); // 45%
  static const Color textDisabled = Color(0x3DFFFFFF); // 24%
}

class AppGradients {
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFF28123), Color(0xFFE05C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFFA855F7), Color(0xFF7E22CE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardOverlay = LinearGradient(
    colors: [Color(0x1FFFFFFF), Color(0x05FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppShadows {
  static final List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: AppColors.primaryOrange.withOpacity(0.4),
      blurRadius: 18,
      spreadRadius: 1,
      offset: const Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> cardSubtle = [
    BoxShadow(
      color: Colors.black.withOpacity(0.35),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDark,
      primaryColor: AppColors.primaryOrange,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryOrange,
        secondary: AppColors.accentBlue,
        surface: AppColors.surfaceCard,
        error: AppColors.dangerRed,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceCard,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme,
      ),
    );
  }
}
