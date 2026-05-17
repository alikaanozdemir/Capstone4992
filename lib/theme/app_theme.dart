import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF0D1117);
  static const bgCard = Color(0xFF161B22);
  static const bgCard2 = Color(0xFF1C2230);
  static const green = Color(0xFF1DB954);
  static const greenDark = Color(0xFF158A3E);
  static const greenLight = Color(0xFF4ADE80);
  static const teal = Color(0xFF00B4D8);
  static const border = Color(0xFF2A3040);
  static const text = Color(0xFFE6EDF3);
  static const textSub = Color(0xFF8B949E);
  static const textMuted = Color(0xFF4A5568);
  static const white = Color(0xFFFFFFFF);
  static const badgeTSID = Color(0xFF1DB954);
  static const badgeTID = Color(0xFF00B4D8);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.green,
          secondary: AppColors.teal,
          surface: AppColors.bgCard,
          background: AppColors.bg,
        ),
        textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme).copyWith(
          bodyLarge: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
          bodyMedium: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
          bodySmall: GoogleFonts.dmSans(color: AppColors.textSub, fontSize: 12),
          titleLarge: GoogleFonts.dmSans(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w700),
          titleMedium: GoogleFonts.dmSans(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600),
          titleSmall: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
          labelSmall: GoogleFonts.dmSans(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w700),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bg,
          elevation: 0,
          titleTextStyle: GoogleFonts.dmSans(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: const IconThemeData(color: AppColors.text),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.bgCard,
          selectedItemColor: AppColors.green,
          unselectedItemColor: AppColors.textMuted,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        dividerColor: AppColors.border,
        iconTheme: const IconThemeData(color: AppColors.textSub),
      );
}
