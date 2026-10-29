import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/data/models/customer.dart';

class CallListenerService {
  static final CallListenerService instance = CallListenerService._();
  factory CallListenerService() => instance;
  CallListenerService._();

  static const _prefKey = 'call_detect_enabled';
  static const _eventChannel = EventChannel('ir.apadanasleep.customer_callbook/phone_state');
  static const _methodChannel = MethodChannel('ir.apadanasleep.customer_callbook/call_log');

  final _customerService = CustomerService();
  final _notifications = FlutterLocalNotificationsPlugin();
  StreamSubscription? _sub;
  bool _isListening = false;
  bool _notifReady = false;
  String? _lastIncoming;
  bool get isListening => _isListening;

  Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefKey) ?? false;
  }

  Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefKey, v);
  }

  Future<void> initNotifications() async {
    if (_notifReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(const InitializationSettings(android: android));
    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'incoming_calls',
        'تماس‌های ورودی',
        description: 'نمایش نام مشتری هنگام تماس',
        importance: Importance.max,
        playSound: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'call_monitor',
        'شناسایی تماس',
        description: 'سرویس شناسایی تماس فعال است',
        importance: Importance.low,
      ),
    );
    _notifReady = true;
  }

  Future<bool> requestPermissions() async {
    final phone = await Permission.phone.request();
    await Permission.contacts.request();
    await Permission.notification.request();
    return phone.isGranted;
  }

  Future<bool> enableAndStart() async {
    await initNotifications();
    final ok = await requestPermissions();
    if (!ok) return false;
    await setEnabled(true);
    await startListening();
    if (_isListening) await _showMonitorNotification();
    return _isListening;
  }

  Future<void> disableAndStop() async {
    await setEnabled(false);
    await stopListening();
    await _notifications.cancel(9001);
  }

  Future<void> restoreIfEnabled() async {
    if (await isEnabled()) {
      await initNotifications();
      if (await Permission.phone.isGranted) {
        await startListening();
        try {
          await _methodChannel.invokeMethod('startCallMonitor');
        } catch (_) {}
        if (_isListening) await _showMonitorNotification();
      }
    }
  }

  Future<void> startListening() async {
    if (_isListening) return;
    await initNotifications();
    if (!await Permission.phone.isGranted) {
      debugPrint('CallListener: no phone permission');
      return;
    }

    try {
      await _methodChannel.invokeMethod('startPhoneListen');
      try {
        await _methodChannel.invokeMethod('startCallMonitor');
      } catch (e) {
        debugPrint("startCallMonitor: $e");
      }
    } catch (e) {
      debugPrint('startPhoneListen native: $e');
    }

    _sub?.cancel();
    _sub = _eventChannel.receiveBroadcastStream().listen((event) async {
      try {
        if (event is! Map) return;
        final status = event['status']?.toString() ?? '';
        final number = (event['number'] ?? '').toString().trim();

        if (status == 'incoming') {
          if (number.isEmpty) return;
          _lastIncoming = number;
          final customer = await _customerService.findByPhone(number);
          if (customer != null) {
            await _customerService.recordCall(number, name: customer.name, type: 1);
            await _showCallNotification(number, customer);
          } else {
            // شماره در دفترچه نیست — فقط اعلان ساده هنگام زنگ
            await _showUnknownRinging(number);
          }
          return;
        }

        if (status == 'idle') {
          final n = number.isNotEmpty ? number : (_lastIncoming ?? '');
          _lastIncoming = null;
          if (n.isEmpty) return;
          final customer = await _customerService.findByPhone(n);
          if (customer == null) {
            // بعد از قطع تماس: پیشنهاد ذخیره
            await _showSavePrompt(n);
          }
        }
      } catch (e) {
        debugPrint('CallListener handle: $e');
      }
    }, onError: (e) {
      debugPrint('CallListener stream error: $e');
    });

    _isListening = true;
    debugPrint('CallListener: native stream started');
  }

  Future<void> stopListening() async {
    _sub?.cancel();
    _sub = null;
    _isListening = false;
    try {
      await _methodChannel.invokeMethod('stopPhoneListen');
      try {
        await _methodChannel.invokeMethod('stopCallMonitor');
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _showMonitorNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'call_monitor',
      'شناسایی تماس',
      channelDescription: 'سرویس شناسایی تماس فعال است',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
    );
    await _notifications.show(
      9001,
      'شناسایی تماس فعال است',
      'با تماس ورودی، نام مشتری نمایش داده می‌شود',
      const NotificationDetails(android: androidDetails),
    );
  }


  Future<void> _showUnknownRinging(String number) async {
    const androidDetails = AndroidNotificationDetails(
      'incoming_calls',
      'تماس‌های ورودی',
      channelDescription: 'نمایش اطلاعات تماس‌گیرنده',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _notifications.show(
      1002,
      'تماس ورودی',
      '${Customer.displayPhone(number)} · در دفترچه نیست',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _showSavePrompt(String number) async {
    const androidDetails = AndroidNotificationDetails(
      'incoming_calls',
      'تماس‌های ورودی',
      channelDescription: 'نمایش اطلاعات تماس‌گیرنده',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _notifications.show(
      1003,
      'ذخیره این شماره؟',
      '${Customer.displayPhone(number)} در مخاطبین دفترچه نیست — اپ را باز کنید و اضافه کنید',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _showCallNotification(String number, Customer? customer) async {
    final title = customer != null ? 'تماس: ${customer.name}' : 'تماس ورودی';
    final note = (customer?.note ?? '').trim();
    final body = customer != null
        ? (note.isNotEmpty
            ? '${Customer.displayPhone(number)} · $note'
            : '${Customer.displayPhone(number)} · ${customer.callCount} تماس · ${customer.tag}')
        : '${Customer.displayPhone(number)} · در دفترچه نیست';

    const androidDetails = AndroidNotificationDetails(
      'incoming_calls',
      'تماس‌های ورودی',
      channelDescription: 'نمایش اطلاعات تماس‌گیرنده',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );

    await _notifications.show(
      1001,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }
}
