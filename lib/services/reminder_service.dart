import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/core/utils/jalali.dart';

class ReminderService {
  static final instance = ReminderService._();
  ReminderService._();

  final _notifications = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(const InitializationSettings(android: android));
    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'reminders',
        'یادآوری تماس',
        description: 'اعلان زمان‌دار پیگیری مشتری',
        importance: Importance.high,
      ),
    );
    _ready = true;
  }

  int _id(Customer c) => c.id.hashCode & 0x7fffffff;

  Future<void> schedule(Customer c) async {
    await init();
    final when = c.reminderAt;
    if (when == null) {
      await cancel(c);
      return;
    }
    await cancel(c);
    if (when.isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
      // سررسید گذشته — اعلان فوری
      await _notifications.show(
        _id(c),
        'یادآوری تماس: ${c.name}',
        '${Customer.displayPhone(c.phone)} · ${Jalali.format(when, withTime: true)}',
        _details(),
      );
      return;
    }
    final scheduled = tz.TZDateTime.from(when, tz.local);
    try {
      await _notifications.zonedSchedule(
        _id(c),
        'یادآوری تماس: ${c.name}',
        'الان زمان تماس با ${Customer.displayPhone(c.phone)} است',
        scheduled,
        _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // fallback بدون exact
      try {
        await _notifications.zonedSchedule(
          _id(c),
          'یادآوری تماس: ${c.name}',
          'الان زمان تماس با ${Customer.displayPhone(c.phone)} است',
          scheduled,
          _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (_) {}
    }
  }

  Future<void> cancel(Customer c) async {
    await init();
    await _notifications.cancel(_id(c));
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'یادآوری تماس',
          channelDescription: 'اعلان زمان‌دار پیگیری مشتری',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      );

  /// یادآوری‌های سررسید (برای وقتی اپ باز می‌شود)
  Future<int> checkDueReminders() async {
    await init();
    return 0;
  }
}
