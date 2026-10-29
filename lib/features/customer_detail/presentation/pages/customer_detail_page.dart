import 'package:customer_callbook/shared/widgets/jalali_picker.dart';
import 'package:customer_callbook/services/reminder_service.dart';
import 'package:customer_callbook/shared/widgets/customer_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/core/theme/tag_colors.dart';
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/data/models/call_record.dart';
import 'package:customer_callbook/core/utils/jalali.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/features/add_customer/presentation/pages/add_customer_page.dart';
import 'package:customer_callbook/shared/widgets/elevated_icon_button.dart';
import 'package:customer_callbook/data/services/note_templates_service.dart';

class CustomerDetailPage extends StatefulWidget {
  final Customer customer;
  const CustomerDetailPage({super.key, required this.customer});

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late Customer _customer;
  final _service = CustomerService();
  final _noteCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  List<CallRecord> _history = [];
  List<String> _templates = [];

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _noteCtrl.text = _customer.note ?? '';
    _cityCtrl.text = _customer.city ?? '';
    _amountCtrl.text = _customer.orderAmount != null ? _customer.orderAmount!.toStringAsFixed(0) : '';
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final h = await _service.getCallHistory(phone: _customer.phone, limit: 30);
    final tpls = await NoteTemplatesService.instance.getAll();
    if (mounted) setState(() {
      _history = h;
      _templates = tpls;
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _cityCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  bool get _mobile => Customer.isMobile(_customer.phone);

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: Customer.normalizePhone(_customer.phone));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      final u = await _service.recordCall(_customer.phone, name: _customer.name);
      setState(() => _customer = u);
      _loadHistory();
    }
  }

  Future<void> _sms() async {
    if (!_mobile) return;
    final uri = Uri(scheme: 'sms', path: Customer.normalizePhone(_customer.phone));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp() async {
    if (!_mobile) return;
    final uri = Uri.parse('https://wa.me/${Customer.toWhatsAppNumber(_customer.phone)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: Customer.normalizePhone(_customer.phone)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شماره کپی شد'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    final u = _customer.copyWith(favorite: !_customer.favorite);
    await _service.update(u);
    setState(() => _customer = u);
  }

  Future<void> _edit() async {
    final r = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(builder: (_) => AddCustomerPage(editCustomer: _customer)),
    );
    if (r != null) {
      setState(() {
        _customer = r;
        _noteCtrl.text = r.note ?? '';
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف مشتری؟'),
        content: Text('«${_customer.name}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('حذف', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok == true) {
      await _service.delete(_customer.id);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _saveNote() async {
    final u = _customer.copyWith(note: _noteCtrl.text.trim());
    await _service.update(u);
    setState(() => _customer = u);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('یادداشت ذخیره شد'), backgroundColor: AppColors.success),
      );
    }
  }

  Color _statusColor(String s) {
    switch (CustomerStatus.normalize(s)) {
      case CustomerStatus.success:
        return const Color(0xFF22C55E);
      case CustomerStatus.negotiating:
        return const Color(0xFF8B5CF6);
      case CustomerStatus.tracking:
        return const Color(0xFFF59E0B);
      case CustomerStatus.lost:
        return const Color(0xFFEF4444);
      default:
        return AppColors.primary;
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    return Jalali.format(dt, withTime: false);
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '—';
    return Jalali.timeAgoOrJalali(dt);
  }



  Widget _infoRow(IconData icon, String label, String value, {bool ltr = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.left,
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _remChip(String label, DateTime Function() whenFn) {
    return ActionChip(
      avatar: const Icon(Icons.alarm, size: 16),
      label: Text(label),
      onPressed: () async {
        final w = whenFn();
        final u = _customer.copyWith(reminderAt: w);
        await _service.update(u);
        await ReminderService.instance.schedule(u);
        setState(() => _customer = u);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('یادآوری و اعلان: ${Jalali.format(w, withTime: true)}')),
          );
        }
      },
    );
  }

  Color _avatarColor(String name) {
    final colors = AppColors.avatarPalette;
    return colors[name.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = Customer.phoneTypeLabel(_customer.phone);
    final isVip = _customer.callCount >= 5;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(_customer.favorite ? Icons.star : Icons.star_border, color: _customer.favorite ? AppColors.warning : null),
            onPressed: _toggleFavorite,
            tooltip: 'ویژه',
          ),
          IconButton(icon: Icon(Icons.delete_outline, color: AppColors.danger), onPressed: _delete),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          children: [
            CustomerAvatar(name: _customer.name, tag: _customer.tag, favorite: _customer.favorite, size: 72),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_customer.favorite) ...[
                  Icon(Icons.star, color: AppColors.warning, size: 18),
                  const SizedBox(width: 4),
                ],
                Flexible(child: Text(_customer.name, style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _Chip(label: _customer.tag, color: TagColors.instance.of(_customer.tag)),
                _Chip(label: typeLabel, color: _mobile ? AppColors.accent : AppColors.textMuted),
                if (isVip) _Chip(label: 'پرتردد', color: AppColors.warning),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onLongPress: _copy,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    Customer.displayPhone(_customer.phone),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Icons.copy, size: 18, color: AppColors.textMuted),
                    onPressed: _copy,
                    tooltip: 'کپی شماره',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // اکشن‌ها — پیامک/واتساپ فقط موبایل
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedIconButton(icon: Icons.phone_rounded, label: 'تماس', color: AppColors.accent, onTap: _call),
                if (_mobile) ElevatedIconButton(icon: Icons.sms_rounded, label: 'پیامک', color: AppColors.info, onTap: _sms),
                if (_mobile) ElevatedIconButton(icon: Icons.chat_rounded, label: 'واتساپ', color: const Color(0xFF25D366), onTap: _whatsapp),
                ElevatedIconButton(icon: Icons.edit_rounded, label: 'ویرایش', color: AppColors.primary, onTap: _edit),
              ],
            ),
            if (!_mobile) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'این شماره موبایل نیست؛ پیامک و واتساپ فقط برای موبایل فعال است.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(child: _InfoCol(title: 'تعداد تماس', value: '${_customer.callCount}')),
                  Expanded(child: _InfoCol(title: 'آخرین تماس', value: _timeAgo(_customer.lastCallAt))),
                  Expanded(child: _InfoCol(title: 'اولین تماس', value: _fmt(_customer.firstCallAt))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: Text('یادداشت', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 10),
            if (_templates.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: _templates.map((tpl) {
                    return ActionChip(
                      label: Text(tpl, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        final cur = _noteCtrl.text.trim();
                        _noteCtrl.text = cur.isEmpty ? tpl : '$cur\n$tpl';
                        _noteCtrl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _noteCtrl.text.length),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            if (_templates.isNotEmpty) const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'یادداشت فروش، پیگیری سفارش...'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _saveNote, child: const Text('ذخیره یادداشت')),
            ),
            const SizedBox(height: 24),
            
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text('اطلاعات پایه', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ColorInfoTile(
                    icon: Icons.phone_rounded,
                    color: const Color(0xFF6366F1),
                    label: 'شماره',
                    value: Customer.normalizePhone(_customer.phone),
                    ltr: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ColorInfoTile(
                    icon: Icons.label_rounded,
                    color: const Color(0xFF8B5CF6),
                    label: 'دسته',
                    value: _customer.tag.isEmpty ? '—' : _customer.tag,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ColorInfoTile(
                    icon: Icons.flag_rounded,
                    color: Color(CustomerStatus.colorValue(_customer.status)),
                    label: 'وضعیت',
                    value: CustomerStatus.normalize(_customer.status),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ColorInfoTile(
                    icon: Icons.event_rounded,
                    color: const Color(0xFF10B981),
                    label: 'تاریخ ثبت',
                    value: Jalali.format(_customer.createdAt),
                  ),
                ),
              ],
            ),
Align(
              alignment: Alignment.centerRight,
              child: Text('وضعیت فروش', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.8,
              children: CustomerStatus.all.map((s) {
                final selected = CustomerStatus.normalize(_customer.status) == s;
                final c = Color(CustomerStatus.colorValue(s));
                return InkWell(
                  onTap: () async {
                    final u = _customer.copyWith(status: s);
                    await _service.update(u);
                    setState(() => _customer = u);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? c : AppColors.border, width: selected ? 1.6 : 1),
                      color: selected ? c.withOpacity(0.14) : AppColors.surfaceElevated,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            s,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, color: selected ? c : AppColors.textPrimary, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: Text('شهر / منطقه', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cityCtrl,
              decoration: const InputDecoration(hintText: 'مثلاً تهران، کرج...'),
              onChanged: (v) async {
                final u = _customer.copyWith(city: v.trim().isEmpty ? null : v.trim());
                // don't save every keystroke - save on button
                setState(() => _customer = u);
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text('مبلغ سفارش (تومان)', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'مثلاً 8500000'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final amt = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
                  final u = _customer.copyWith(
                    city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
                    orderAmount: amt,
                    note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                  );
                  await _service.update(u);
                  setState(() => _customer = u);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('اطلاعات ذخیره شد'), backgroundColor: AppColors.success),
                    );
                  }
                },
                child: const Text('ذخیره شهر و مبلغ'),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.alarm_rounded, color: AppColors.warning, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text('یادآوری تماس', style: Theme.of(context).textTheme.titleMedium)),
                      PopupMenuButton<String>(
                        tooltip: 'تنظیم یادآوری',
                        onSelected: (v) async {
                          DateTime? when;
                          final n = DateTime.now();
                          switch (v) {
                            case '1h': when = n.add(const Duration(hours: 1)); break;
                            case '3h': when = n.add(const Duration(hours: 3)); break;
                            case 'eve':
                              when = DateTime(n.year, n.month, n.day, 18, 0);
                              if (!when.isAfter(n)) when = n.add(const Duration(hours: 2));
                              break;
                            case 'tmr': when = DateTime(n.year, n.month, n.day + 1, 10, 0); break;
                            case '3d': when = DateTime(n.year, n.month, n.day + 3, 10, 0); break;
                            case '1w': when = DateTime(n.year, n.month, n.day + 7, 10, 0); break;
                            case 'pick':
                              when = await showJalaliDateTimePicker(context, initial: _customer.reminderAt);
                              break;
                          }
                          if (when == null || !mounted) return;
                          final u = _customer.copyWith(reminderAt: when);
                          await _service.update(u);
                          await ReminderService.instance.schedule(u);
                          setState(() => _customer = u);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('یادآوری: ${Jalali.format(when, withTime: true)}')),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: '1h', child: Text('۱ ساعت بعد')),
                          PopupMenuItem(value: '3h', child: Text('۳ ساعت بعد')),
                          PopupMenuItem(value: 'eve', child: Text('امروز عصر')),
                          PopupMenuItem(value: 'tmr', child: Text('فردا')),
                          PopupMenuItem(value: '3d', child: Text('۳ روز بعد')),
                          PopupMenuItem(value: '1w', child: Text('یک هفته')),
                          PopupMenuItem(value: 'pick', child: Text('تاریخ شمسی…')),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_alarm_rounded, size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text('تنظیم', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_customer.reminderAt != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            Jalali.format(_customer.reminderAt!, withTime: true),
                            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.danger, size: 20),
                          onPressed: () async {
                            final u = _customer.copyWith(clearReminder: true);
                            await _service.update(u);
                            await ReminderService.instance.cancel(u);
                            setState(() => _customer = u);
                          },
                        ),
                      ],
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('یادآوری تنظیم نشده', style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            Align(
              alignment: Alignment.centerRight,
              child: Text('فعالیت‌های ثبت‌شده', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 6),
            Text('تماس‌ها و پیگیری‌های این مشتری', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (_history.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text('هنوز فعالیتی ثبت نشده', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              )
            else
              ..._history.map((r) {
                final color = r.type == 1
                    ? AppColors.accent
                    : r.type == 3
                        ? AppColors.danger
                        : AppColors.info;
                final chipBg = color.withOpacity(0.12);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _call(),
                              icon: Icon(Icons.phone_rounded, color: AppColors.accent, size: 20),
                            ),
                            const Spacer(),
                            Text(Jalali.format(r.at), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(8)),
                              child: Text(r.typeLabel, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                            if (_customer.tag.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text('دسته: ${_customer.tag}', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                              ),
                            Builder(builder: (_) {
                              final st = (r.resultStatus != null && r.resultStatus!.isNotEmpty)
                                  ? r.resultStatus!
                                  : _customer.status;
                              final col = _statusColor(st);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: col.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                                child: Text(st, style: TextStyle(color: col, fontWeight: FontWeight.w600, fontSize: 12)),
                              );
                            }),
                          ],
                        ),
                        if (_customer.note != null && _customer.note!.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(_customer.note!, style: Theme.of(context).textTheme.bodyMedium),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule, size: 14, color: AppColors.warning),
                                const SizedBox(width: 4),
                                Text(_timeAgo(r.at), style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}



class _InfoCol extends StatelessWidget {
  final String title;
  final String value;
  const _InfoCol({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center, maxLines: 1),
      ],
    );
  }
}


class _ColorInfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool ltr;
  const _ColorInfoTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.ltr = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
