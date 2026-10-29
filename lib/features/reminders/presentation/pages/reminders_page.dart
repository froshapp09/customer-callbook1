import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/core/utils/jalali.dart';
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/features/customer_detail/presentation/pages/customer_detail_page.dart';
import 'package:customer_callbook/shared/widgets/customer_avatar.dart';
import 'package:customer_callbook/services/reminder_service.dart';

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});
  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  final _service = CustomerService();
  List<Customer> _due = [];
  List<Customer> _up = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final due = await _service.remindersDueToday();
    final up = await _service.remindersUpcoming();
    if (mounted) setState(() { _due = due; _up = up; _loading = false; });
  }

  Future<void> _call(Customer c) async {
    final uri = Uri(scheme: 'tel', path: Customer.normalizePhone(c.phone));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      await _service.recordCall(c.phone, name: c.name);
    }
  }

  Future<void> _copy(Customer c) async {
    await Clipboard.setData(ClipboardData(text: Customer.normalizePhone(c.phone)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شماره کپی شد'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _done(Customer c) async {
    final u = c.copyWith(clearReminder: true);
    await _service.update(u);
    await ReminderService.instance.cancel(u);
    _load();
  }

  Widget _card(Customer c, {bool overdue = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CustomerAvatar(name: c.name, tag: c.tag, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      Customer.displayPhone(c.phone),
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _badge(
                overdue ? 'عقب‌افتاده' : 'یادآوری',
                overdue ? AppColors.danger : AppColors.warning,
              ),
              _badge(Jalali.format(c.reminderAt!, withTime: true), AppColors.primary),
              _badge(c.status, Color(CustomerStatus.colorValue(c.status))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(c),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('کپی'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _call(c),
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: const Text('تماس'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _done(c),
                tooltip: 'انجام شد',
                icon: Icon(Icons.check_circle_rounded, color: AppColors.success),
              ),
            ],
          ),
          TextButton(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: c)));
              _load();
            },
            child: const Text('مشاهده مشتری'),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return Scaffold(
      appBar: AppBar(title: const Text('امروز زنگ بزن')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_due.isEmpty && _up.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available_rounded, size: 56, color: AppColors.textMuted),
                        const SizedBox(height: 14),
                        Text('یادآوری‌ای نیست', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          'از صفحه هر مشتری، یادآوری تنظیم کنید.\nدر ساعت مقرر اعلان هم می‌آید.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_due.isNotEmpty) ...[
                      Text('امروز و عقب‌افتاده', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      ..._due.map((c) {
                        final rd = DateTime(c.reminderAt!.year, c.reminderAt!.month, c.reminderAt!.day);
                        return _card(c, overdue: rd.isBefore(start));
                      }),
                    ],
                    if (_up.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('روزهای آینده', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      ..._up.map((c) => _card(c)),
                    ],
                  ],
                ),
    );
  }
}
