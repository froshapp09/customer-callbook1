import 'package:flutter/material.dart';

/// تم روشن شیشه‌ای — مطابق نمونه مرجع
class AppColors {
  static bool isDark = false;

  static const Color background = Color(0xFFEEF0FA);
  static const Color backgroundEnd = Color(0xFFE8E4F8);
  static const Color surface = Color(0xF2FFFFFF);
  static const Color surfaceSolid = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryDark = Color(0xFF5548E0);
  static const Color accent = Color(0xFF16A34A);
  static const Color success = Color(0xFF16A34A);
  static const Color textPrimary = Color(0xFF1A1730);
  static const Color textSecondary = Color(0xFF5C5878);
  static const Color textMuted = Color(0xFF9B97B0);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color info = Color(0xFF2563EB);
  static const Color border = Color(0xFFE2E0F0);
  static const Color chipBg = Color(0xFFEEECFF);
  static const Color shadow = Color(0x1A5E52E0);
  static const Color navBar = Color(0xFFFFFFFF);

  static const List<Color> avatarPalette = [
    Color(0xFF7C6CF0),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFF14B8A6),
  ];

  static const Map<String, int> defaultTagColors = {
    'مشتری': 0xFF7C6CF0,
    'همکار': 0xFF22C55E,
    'سایر': 0xFF94A3B8,
  };
}
