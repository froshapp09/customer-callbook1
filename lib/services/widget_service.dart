import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/data/models/customer.dart';

class WidgetService {
  static final instance = WidgetService._();
  WidgetService._();

  static const androidName = 'DaftarcheWidgetProvider';
  static const qualifiedAndroidName =
      'ir.apadanasleep.customer_callbook.DaftarcheWidgetProvider';

  Future<void> update() async {
    try {
      final service = CustomerService();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);

      final history = await service.getCallHistory(limit: 100);
      final todayRecords = history.where((r) {
        final at = r.at.toLocal();
        return !at.isBefore(start);
      }).toList()
        ..sort((a, b) => b.at.compareTo(a.at));

      final customers = await service.getAll();
      String nameFor(String phone) {
        for (final c in customers) {
          if (Customer.samePhone(c.phone, phone)) return c.name;
        }
        return Customer.displayPhone(phone);
      }

      final lines = <String>[];
      final seen = <String>{};
      for (final r in todayRecords) {
        final key = Customer.matchKey(r.phone);
        if (seen.contains(key)) continue;
        seen.add(key);
        final t = r.at.toLocal();
        final hh = t.hour.toString().padLeft(2, '0');
        final mm = t.minute.toString().padLeft(2, '0');
        final type = r.type == 1 ? '↓' : (r.type == 2 ? '↑' : '✕');
        lines.add('$hh:$mm $type ${nameFor(r.phone)}');
        if (lines.length >= 3) break;
      }

      if (lines.isEmpty) {
        final todayCust = customers.where((c) {
          final d = c.lastCallAt;
          if (d == null || c.callCount <= 0) return false;
          final l = d.toLocal();
          return l.year == now.year && l.month == now.month && l.day == now.day;
        }).toList()
          ..sort((a, b) => b.lastCallAt!.compareTo(a.lastCallAt!));
        for (final c in todayCust.take(3)) {
          final t = c.lastCallAt!.toLocal();
          final hh = t.hour.toString().padLeft(2, '0');
          final mm = t.minute.toString().padLeft(2, '0');
          lines.add('$hh:$mm  ${c.name}');
        }
      }

      final count = todayRecords.isNotEmpty ? '${todayRecords.length}' : '${lines.length}';

      await HomeWidget.saveWidgetData<String>('widget_count', count);
      await HomeWidget.saveWidgetData<String>(
        'widget_line1',
        lines.isNotEmpty ? lines[0] : 'تماس امروزی ثبت نشده',
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_line2',
        lines.length > 1 ? lines[1] : '',
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_line3',
        lines.length > 2 ? lines[2] : '',
      );

      await HomeWidget.updateWidget(
        name: androidName,
        androidName: androidName,
        qualifiedAndroidName: qualifiedAndroidName,
      );

      // پشتیبان: آپدیت نیتیو
      try {
        const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
        await ch.invokeMethod('updateWidget');
      } catch (_) {}
    } catch (_) {}
  }
}
