import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

/// لایسنس
/// فعلاً بیلد پیش‌فرض = شخصی بدون محدودیت
/// بعداً برای بازار: --dart-define=FOROSHYAR_CHANNEL=store
class LicenseService {
  LicenseService._();
  static final instance = LicenseService._();

  static const maxFreeCustomers = 100;
  static const skuPro = 'foroshyar_pro';
  static const _prefPro = 'is_pro';
  static const _channel = MethodChannel('ir.apadanasleep.customer_callbook/bazaar_billing');

  static const channel = String.fromEnvironment(
    'FOROSHYAR_CHANNEL',
    defaultValue: 'personal',
  );

  static bool get isPersonalBuild => channel != 'store';
  static bool get isStoreBuild => channel == 'store';

  static const rsaKeyPlaceholder = 'BAZAAR_RSA_KEY_PLACEHOLDER';

  Future<bool> isPro() async {
    if (isPersonalBuild) return true;
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefPro) ?? false;
  }

  Future<void> setPro(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefPro, v);
  }

  Future<bool> canAddCustomer(int currentCount) async {
    if (await isPro()) return true;
    return currentCount < maxFreeCustomers;
  }

  Future<String> limitMessage(int currentCount) async {
    if (isPersonalBuild) return 'نسخه شخصی — بدون محدودیت';
    if (await isPro()) return 'نسخه پرو فعال است';
    final left = (maxFreeCustomers - currentCount).clamp(0, maxFreeCustomers);
    return 'رایگان: $currentCount از $maxFreeCustomers — باقی‌مانده: $left';
  }

  Future<bool> purchasePro() async {
    if (isPersonalBuild) {
      await setPro(true);
      return true;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('purchase', {'sku': skuPro});
      if (ok == true) {
        await setPro(true);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> restorePurchases() async {
    if (isPersonalBuild) {
      await setPro(true);
      return true;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('restore');
      if (ok == true) {
        await setPro(true);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> debugUnlockPro() async {
    await setPro(true);
  }
}
