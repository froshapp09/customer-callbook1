import 'package:flutter/material.dart';
import 'package:customer_callbook/core/utils/text_repair.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/features/add_customer/presentation/pages/add_customer_page.dart';

class CallSyncPage extends StatefulWidget {
  const CallSyncPage({super.key});

  @override
  State<CallSyncPage> createState() => _CallSyncPageState();
}

class _CallSyncPageState extends State<CallSyncPage> {
  static const _channel = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
  final _service = CustomerService();
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final phone = await Permission.phone.request();
      if (!phone.isGranted) {
        setState(() {
          _loading = false;
          _error = 'مجوز تلفن داده نشده.\nتنظیمات → برنامه‌ها → فروشیار → مجوزها → تلفن';
        });
        return;
      }

      final result = await _channel.invokeMethod<List>('getRecentCalls', {'days': 2});
      final list = <Map<String, dynamic>>[];
      if (result != null) {
        for (final item in result) {
          if (item is Map) {
            list.add(Map<String, dynamic>.from(item));
          }
        }
      }
      setState(() {
        _entries = list;
        _loading = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message ?? 'خطا در خواندن تاریخچه تماس';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'خطا: $e\n\nاگر مجوز تلفن را داده‌اید، یک‌بار برنامه را ببندید و دوباره باز کنید.';
      });
    }
  }

  String _typeLabel(String? t) {
    switch (t) {
      case 'incoming':
        return 'ورودی';
      case 'outgoing':
        return 'خروجی';
      case 'missed':
        return 'از دست رفته';
      case 'rejected':
        return 'رد شده';
      default:
        return 'تماس';
    }
  }

  Color _typeColor(String? t) {
    switch (t) {
      case 'incoming':
        return AppColors.success;
      case 'outgoing':
        return AppColors.info;
      case 'missed':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }

  String _timeLabel(int? ts) {
    if (ts == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'امروز $h:$m';
    if (day == today.subtract(const Duration(days: 1))) return 'دیروز $h:$m';
    return '${dt.month}/${dt.day} $h:$m';
  }

  Future<void> _addOrUpdate(Map<String, dynamic> e) async {
    final phone = (e['number'] ?? '').toString().trim();
    if (phone.isEmpty) return;

    final existing = await _service.findByPhone(phone);
    if (existing != null) {
      // فقط یادآوری: قبلاً در دفترچه هست — تماس گوشی را به عنوان تماس اپ ثبت نکن
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('«${existing.name}» از قبل در دفترچه است'), backgroundColor: AppColors.info),
        );
      }
    } else {
      String name = TextRepair.fix((e['name'] ?? '').toString().trim());
      final fromContacts = await _service.lookupNameFromDeviceContacts(phone);
      if (fromContacts != null && fromContacts.isNotEmpty) {
        name = fromContacts;
      } else if (name.isEmpty || name == phone || RegExp(r'^[A-Z0-9.\-_+]+$').hasMatch(name)) {
        name = '';
      }
      if (name.isEmpty) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddCustomerPage(initialPhone: phone)),
        );
      } else {
        // فقط مشتری — جزو تماس اپ / سابقه تماس حساب نشود
        final __c = await _service.add(Customer(
          name: name,
          phone: phone,
          callCount: 0,
          firstCallAt: null,
          lastCallAt: null,
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('«$name» اضافه شد'), backgroundColor: AppColors.success),
          );
        }
      }
    }
    _load();
  }

  Future<void> _addAllMissing() async {
    int added = 0;
    final seen = <String>{};
    for (final e in _entries) {
      final phone = (e['number'] ?? '').toString().trim();
      if (phone.isEmpty) continue;
      final key = phone.replaceAll(RegExp(r'\D'), '');
      if (seen.contains(key)) continue;
      seen.add(key);
      if (await _service.findByPhone(phone) != null) continue;

      String name = TextRepair.fix((e['name'] ?? '').toString().trim());
      if (name.isEmpty || name == phone) {
        name = await _service.lookupNameFromDeviceContacts(phone) ?? phone;
      }
      final __c = await _service.add(Customer(
        name: name,
        phone: phone,
        callCount: 0,
        firstCallAt: null,
        lastCallAt: null,
      ));
      added++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$added مشتری جدید اضافه شد'), backgroundColor: AppColors.success),
      );
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تماس‌های گوشی'),
        actions: [
          if (_entries.isNotEmpty)
            TextButton(onPressed: _addAllMissing, child: Text('افزودن همه')),
          IconButton(icon: Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_disabled, size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 20),
                        ElevatedButton(onPressed: () => openAppSettings(), child: const Text('تنظیمات مجوزها')),
                        TextButton(onPressed: _load, child: const Text('تلاش مجدد')),
                      ],
                    ),
                  ),
                )
              : _entries.isEmpty
                  ? Center(child: Text('تماس اخیری پیدا نشد', style: TextStyle(color: AppColors.textMuted)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final e = _entries[index];
                        final phone = (e['number'] ?? '—').toString();
                        final name = (e['name'] as String?)?.trim();
                        final hasName = name != null && name.isNotEmpty && name != phone;
                        final type = e['type'] as String?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.phone_callback, color: _typeColor(type), size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(hasName ? name : phone, style: Theme.of(context).textTheme.titleMedium),
                                      if (hasName) Text(phone, style: Theme.of(context).textTheme.bodySmall),
                                      Text(
                                        '${_typeLabel(type)}  •  ${_timeLabel(e['timestamp'] as int?)}  •  ${Customer.phoneTypeLabel(phone)}',
                                        style: TextStyle(color: _typeColor(type), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(onPressed: () => _addOrUpdate(e), child: const Text('افزودن')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
