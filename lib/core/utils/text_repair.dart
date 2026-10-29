import 'dart:convert';

/// تعمیر متن فارسی که به‌اشتباه به‌صورت Latin-1 / Windows-1252 خوانده شده (mojibake)
class TextRepair {
  // الگوهای رایج mojibake برای UTF-8 فارسی که Latin-1 شده
  static final _mojibake = RegExp(
    r'[ØÙÃÂÆÐÑÝÞßåäöøùúûüýþÿÐñ]',
    unicode: true,
  );
  static final _persian = RegExp(r'[\u0600-\u06FF]');
  // توالی‌های خیلی رایج مثل Ø§ Ù  Ø±
  static final _utf8AsLatin1 = RegExp(r'Ø[\u0080-\u00FF]|Ù[\u0080-\u00FF]|Ã[\u0080-\u00FF]');

  static bool looksBroken(String s) {
    if (s.isEmpty) return false;
    if (_persian.hasMatch(s) && !_mojibake.hasMatch(s)) return false;
    final bad = _mojibake.allMatches(s).length;
    if (bad >= 2) return true;
    if (_utf8AsLatin1.hasMatch(s) && !_persian.hasMatch(s)) return true;
    // اگر بیش از نیمی از کاراکترهای غیرعددی در محدوده Latin-1 extended باشند
    var latinExt = 0;
    var letters = 0;
    for (final u in s.codeUnits) {
      if ((u >= 0x30 && u <= 0x39) || u == 0x20 || u == 0x2D) continue;
      letters++;
      if (u >= 0xC0 && u <= 0xFF) latinExt++;
    }
    return letters >= 3 && latinExt >= 2 && !_persian.hasMatch(s);
  }

  /// UTF-8 که به‌عنوان Latin-1 ذخیره شده را برمی‌گرداند
  static String fix(String input) {
    if (input.isEmpty) return input;
    if (_persian.hasMatch(input) && !_mojibake.hasMatch(input)) return input;

    // تلاش ۱: code units به‌عنوان بایت Latin-1 → UTF-8
    try {
      final bytes = <int>[];
      var ok = true;
      for (final c in input.codeUnits) {
        if (c > 0xFF) {
          ok = false;
          break;
        }
        bytes.add(c);
      }
      if (ok && bytes.isNotEmpty) {
        final fixed = utf8.decode(bytes, allowMalformed: true);
        if (_persian.hasMatch(fixed) && fixed != input) return fixed;
      }
    } catch (_) {}

    // تلاش ۲: اگر خودش کمی فارسی دارد ولی هنوز mojibake دارد
    if (looksBroken(input)) {
      try {
        final bytes = input.codeUnits.where((c) => c <= 0xFF).toList();
        final fixed = utf8.decode(bytes, allowMalformed: true);
        if (_persian.hasMatch(fixed)) return fixed;
      } catch (_) {}
    }
    return input;
  }

  static String fixOr(String input, [String fallback = '']) {
    final f = fix(input);
    return looksBroken(f) ? fallback : f;
  }
}
