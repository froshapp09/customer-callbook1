import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  bool _isDark = true;
  bool get isDark => _isDark;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _isDark = p.getBool('is_dark_theme') ?? true;
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    _isDark = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool('is_dark_theme', value);
    notifyListeners();
  }

  Future<void> toggle() => setDark(!_isDark);
}
