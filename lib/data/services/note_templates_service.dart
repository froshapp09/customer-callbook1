
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_callbook/core/utils/text_repair.dart';

class NoteTemplatesService {
  static final NoteTemplatesService instance = NoteTemplatesService._();
  NoteTemplatesService._();

  static const _key = 'note_templates_v1';
  static const _migratedKey = 'note_templates_user_owned_v1';

  /// پیشنهادهای عمومی (فقط وقتی کاربر هنوز چیزی نساخته — یک‌بار به‌عنوان راهنما)
  static const suggestions = [
    'پیگیری سفارش',
    'علاقه‌مند به خرید',
    'نیاز به مشاوره',
    'تماس مجدد',
  ];

  Future<List<String>> getAll() async {
    final p = await SharedPreferences.getInstance();
    // یک‌بار پاک‌سازی قالب‌های قدیمی اختصاصی اگر هنوز مهاجرت نشده
    if (p.getBool(_migratedKey) != true) {
      await p.setBool(_migratedKey, true);
      // شروع تمیز: کاربر خودش یادداشت بسازد
      await p.setString(_key, jsonEncode([]));
      return [];
    }
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => TextRepair.fix(e.toString()))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<String> items) async {
    final p = await SharedPreferences.getInstance();
    final clean = items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await p.setString(_key, jsonEncode(clean));
    await p.setBool(_migratedKey, true);
  }

  Future<void> add(String text) async {
    final list = await getAll();
    final t = TextRepair.fix(text.trim());
    if (t.isEmpty) return;
    if (!list.contains(t)) list.add(t);
    await saveAll(list);
  }

  Future<void> remove(String text) async {
    final list = await getAll();
    list.remove(text);
    await saveAll(list);
  }
}
