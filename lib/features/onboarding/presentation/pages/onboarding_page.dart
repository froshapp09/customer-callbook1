import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/services/call_listener_service.dart';

/// آموزش یک‌باره فعال‌سازی — ساده، بدون فرم پیچیده
class OnboardingPage extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.onDone});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;
  bool _busy = false;

  final _steps = const [
    (
      Icons.phone_callback_rounded,
      Color(0xFF22C55E),
      'شناسایی تماس',
      'برای تشخیص شماره هنگام تماس ورودی و خروجی، دسترسی تلفن و گزارش تماس لازم است.',
    ),
    (
      Icons.layers_rounded,
      Color(0xFF8B5CF6),
      'نمایش روی صفحه',
      'برای پاپ‌آپ نام مشتری روی صفحه تماس، مجوز «نمایش روی سایر برنامه‌ها» را بدهید.',
    ),
    (
      Icons.notifications_active_rounded,
      Color(0xFF3B82F6),
      'اعلان‌ها',
      'اعلان تماس و یادآوری پیگیری مشتری در ساعت مقرر.',
    ),
    (
      Icons.battery_charging_full_rounded,
      Color(0xFFF59E0B),
      'پایداری سیستم',
      'در گوشی‌های هواوی، شیائومی و سامسونگ: باتری را بدون محدودیت و راه‌اندازی خودکار را روشن کنید تا اپ در پس‌زمینه قطع نشود.',
    ),
  ];

  Future<void> _next() async {
    setState(() => _busy = true);
    try {
      if (_step == 0) {
        await [
          Permission.phone,
          Permission.contacts,
        ].request();
        try {
          // call log may map to phone on some devices
          await Permission.phone.request();
        } catch (_) {}
        await CallListenerService.instance.enableAndStart();
      } else if (_step == 1) {
        try {
          const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
          final can = await ch.invokeMethod<bool>('canDrawOverlays') ?? false;
          if (!can) await ch.invokeMethod('openOverlayPermission');
        } catch (_) {
          await openAppSettings();
        }
      } else if (_step == 2) {
        await Permission.notification.request();
      } else if (_step == 3) {
        await openAppSettings();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      final p = await SharedPreferences.getInstance();
      await p.setBool('onboarding_done_v1', true);
      widget.onDone();
    }
  }

  Future<void> _skip() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarding_done_v1', true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final s = _steps[_step];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _skip, child: const Text('رد کردن')),
              ),
              const SizedBox(height: 8),
              Text('فعال‌سازی فروشیار', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              // progress
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  final on = i <= _step;
                  return Container(
                    width: 28,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: on ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: s.$2.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(s.$1, size: 44, color: s.$2),
              ),
              const SizedBox(height: 24),
              Text(s.$3, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(
                s.$4,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _next,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_step == _steps.length - 1 ? 'تأیید نهایی' : 'گام بعدی'),
                ),
              ),
              if (_step > 0)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _step--),
                  child: const Text('قبلی'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
