import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Accent renkler — her iki modda aynı
class AppColors {
  static const green      = Color(0xFF1DB954);
  static const greenDark  = Color(0xFF158A3E);
  static const greenLight = Color(0xFF4ADE80);
  static const teal       = Color(0xFF00B4D8);
  static const white      = Color(0xFFFFFFFF);
  static const badgeTSID  = Color(0xFF1DB954);
  static const badgeTID   = Color(0xFF00B4D8);

  // Backward-compat statics (dark mode değerleri)
  static const bg       = Color(0xFF0D1117);
  static const bgCard   = Color(0xFF161B22);
  static const bgCard2  = Color(0xFF1C2230);
  static const border   = Color(0xFF2A3040);
  static const text     = Color(0xFFE6EDF3);
  static const textSub  = Color(0xFF8B949E);
  static const textMuted= Color(0xFF4A5568);

  static AppColorSet of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColorSet.dark
        : AppColorSet.light;
  }
}

class AppColorSet {
  final Color bg;
  final Color bgCard;
  final Color bgCard2;
  final Color border;
  final Color text;
  final Color textSub;
  final Color textMuted;

  const AppColorSet({
    required this.bg,
    required this.bgCard,
    required this.bgCard2,
    required this.border,
    required this.text,
    required this.textSub,
    required this.textMuted,
  });

  static const dark = AppColorSet(
    bg:        Color(0xFF0D1117),
    bgCard:    Color(0xFF161B22),
    bgCard2:   Color(0xFF1C2230),
    border:    Color(0xFF2A3040),
    text:      Color(0xFFE6EDF3),
    textSub:   Color(0xFF8B949E),
    textMuted: Color(0xFF4A5568),
  );

  static const light = AppColorSet(
    bg:        Color(0xFFF5F7FA),
    bgCard:    Color(0xFFFFFFFF),
    bgCard2:   Color(0xFFEEF1F5),
    border:    Color(0xFFDDE1E7),
    text:      Color(0xFF111827),
    textSub:   Color(0xFF4B5563),
    textMuted: Color(0xFF9CA3AF),
  );
}

class AppTheme {
  static ThemeData get dark => _build(Brightness.dark, AppColorSet.dark);
  static ThemeData get light => _build(Brightness.light, AppColorSet.light);

  static ThemeData _build(Brightness brightness, AppColorSet c) {
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.green,
        onPrimary: Colors.white,
        secondary: AppColors.teal,
        onSecondary: Colors.white,
        surface: c.bgCard,
        onSurface: c.text,
        background: c.bg,
        onBackground: c.text,
        error: const Color(0xFFE74C3C),
        onError: Colors.white,
        outline: c.border,
        surfaceVariant: c.bgCard2,
        onSurfaceVariant: c.textSub,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(
        brightness == Brightness.dark
            ? ThemeData.dark().textTheme
            : ThemeData.light().textTheme,
      ).copyWith(
        bodyLarge:   GoogleFonts.dmSans(color: c.text, fontSize: 15),
        bodyMedium:  GoogleFonts.dmSans(color: c.text, fontSize: 14),
        bodySmall:   GoogleFonts.dmSans(color: c.textSub, fontSize: 12),
        titleLarge:  GoogleFonts.dmSans(color: c.text, fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: GoogleFonts.dmSans(color: c.text, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall:  GoogleFonts.dmSans(color: c.text, fontSize: 14, fontWeight: FontWeight.w600),
        labelSmall:  GoogleFonts.dmSans(color: c.textSub, fontSize: 10, fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        elevation: 0,
        titleTextStyle: GoogleFonts.dmSans(color: c.text, fontSize: 18, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: c.text),
      ),
      dividerColor: c.border,
      iconTheme: IconThemeData(color: c.textSub),
    );
  }
}
