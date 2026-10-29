import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

class TagColors {
  static final TagColors instance = TagColors._();
  TagColors._();

  final Map<String, int> _argb = {
    for (final e in AppColors.defaultTagColors.entries) e.key: e.value,
  };

  final List<Color> palette = const [
    Color(0xFF14B8A6),
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFF22C55E),
    Color(0xFF7C6CF0),
    Color(0xFF94A3B8),
    Color(0xFFEF4444),
  ];

  Color of(String tag) => Color(_argb[tag] ?? AppColors.defaultTagColors[tag] ?? 0xFF7C6CF0);

  int argbOf(String tag) => _argb[tag] ?? AppColors.defaultTagColors[tag] ?? 0xFF7C6CF0;

  bool isSelected(String tag, Color c) => (c.value & 0xFFFFFF) == (argbOf(tag) & 0xFFFFFF);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    for (final key in AppColors.defaultTagColors.keys) {
      final v = p.getInt('tag_color_$key');
      if (v != null) _argb[key] = v;
    }
  }

  Future<void> set(String tag, Color color) async {
    final v = color.value;
    _argb[tag] = v;
    final p = await SharedPreferences.getInstance();
    await p.setInt('tag_color_$tag', v);
  }
}
