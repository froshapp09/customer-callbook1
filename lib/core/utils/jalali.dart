/// تبدیل ساده میلادی → شمسی
class Jalali {
  static String format(DateTime dt, {bool withTime = false}) {
    final j = _toJalali(dt.year, dt.month, dt.day);
    final date = '${j[0]}/${j[1].toString().padLeft(2, '0')}/${j[2].toString().padLeft(2, '0')}';
    if (!withTime) return date;
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date  $t';
  }

  static String timeAgoOrJalali(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'همین الان';
    if (d.inMinutes < 60) return '${d.inMinutes} دقیقه پیش';
    if (d.inHours < 24) return '${d.inHours} ساعت پیش';
    if (d.inDays < 7) return '${d.inDays} روز پیش';
    return format(dt, withTime: true);
  }

  static List<int> _toJalali(int gy, int gm, int gd) {
    final g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    var jy = (gy <= 1600) ? 0 : 979;
    gy -= (gy <= 1600) ? 621 : 1600;
    var gy2 = (gm > 2) ? (gy + 1) : gy;
    var days = (365 * gy) + ((gy2 + 3) ~/ 4) - ((gy2 + 99) ~/ 100) + ((gy2 + 399) ~/ 400) - 80 + gd + g_d_m[gm - 1];
    jy += 33 * (days ~/ 12053);
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    final jm = (days < 186) ? 1 + (days ~/ 31) : 7 + ((days - 186) ~/ 30);
    final jd = 1 + ((days < 186) ? (days % 31) : ((days - 186) % 30));
    return [jy, jm, jd];
  }


  static List<int> toJalali(DateTime dt) => _toJalali(dt.year, dt.month, dt.day);

  static const _weekdays = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
  /// DateTime.weekday: 1=Mon ... 7=Sun
  static String weekdayName(DateTime dt) => _weekdays[dt.weekday - 1];

  static String clock(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';


  static int daysInMonth(int jy, int jm) {
    if (jm <= 6) return 31;
    if (jm <= 11) return 30;
    // اسفند: کبیسه تقریبی
    return _isLeap(jy) ? 30 : 29;
  }

  static bool _isLeap(int jy) {
    final breaks = [1, 5, 9, 13, 17, 22, 26, 30];
    final jp = jy - 979;
    final jump = jp ~/ 33;
    final jp2 = jp - jump * 33;
    for (final b in breaks) {
      if (jp2 < b) return false;
      if (jp2 == b) return true;
    }
    return false;
  }

  /// تبدیل شمسی → میلادی
  static DateTime fromJalali(int jy, int jm, int jd, [int hour = 0, int minute = 0]) {
    var gy = (jy <= 979) ? 621 : 1600;
    jy -= (jy <= 979) ? 0 : 979;
    var days = (365 * jy) + ((jy ~/ 33) * 8) + (((jy % 33) + 3) ~/ 4) + 78 + jd + ((jm < 7) ? (jm - 1) * 31 : ((jm - 7) * 30 + 186));
    gy += 400 * (days ~/ 146097);
    days %= 146097;
    if (days > 36524) {
      gy += 100 * (--days ~/ 36524);
      days %= 36524;
      if (days >= 365) days++;
    }
    gy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      gy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    var gd = days + 1;
    final sal_a = [0, 31, ((gy % 4 == 0 && gy % 100 != 0) || (gy % 400 == 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var gm = 0;
    for (gm = 1; gm <= 12 && gd > sal_a[gm]; gm++) {
      gd -= sal_a[gm];
    }
    return DateTime(gy, gm, gd, hour, minute);
  }
}
