import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/data/services/note_templates_service.dart';
import 'package:customer_callbook/data/services/license_service.dart';

class AddCustomerPage extends StatefulWidget {
  final Customer? editCustomer;
  final String? initialPhone;
  final bool fromCall;
  final int callType;
  const AddCustomerPage({
    super.key,
    this.editCustomer,
    this.initialPhone,
    this.fromCall = false,
    this.callType = 1,
  });

  @override
  State<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _city = TextEditingController();
  final _amount = TextEditingController();
  final _service = CustomerService();
  String _tag = 'مشتری';
  String _status = CustomerStatus.tracking;
  DateTime? _reminderAt;
  bool _saving = false;
  List<String> _templates = [];

  @override
  void initState() {
    super.initState();
    if (widget.editCustomer != null) {
      final c = widget.editCustomer!;
      _name.text = c.name;
      _phone.text = c.phone;
      _note.text = c.note ?? '';
      _city.text = c.city ?? '';
      _amount.text = c.orderAmount != null ? c.orderAmount!.toStringAsFixed(0) : '';
      _tag = c.tag;
      _status = c.status;
      _reminderAt = c.reminderAt;
    } else if (widget.initialPhone != null) {
      _phone.text = Customer.normalizePhone(widget.initialPhone!);
      _service.lookupNameFromDeviceContacts(widget.initialPhone!).then((n) {
        if (n != null && mounted && _name.text.isEmpty) {
          setState(() => _name.text = n);
        }
      });
    }
    NoteTemplatesService.instance.getAll().then((list) {
      if (mounted) setState(() => _templates = list);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    _city.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _recordIfNeeded(String phone, String name) async {
    // اگر از تماس آمده یا شماره اولیه داشته (پاپ‌آپ ذخیره)
    final fromCall = widget.fromCall || (widget.initialPhone != null && widget.initialPhone!.trim().isNotEmpty);
    if (!fromCall) return;
    try {
      await _service.recordCall(phone, name: name, type: widget.callType);
    } catch (_) {}
  }

  Future<void> _clearPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_add_phone');
      await prefs.remove('pending_add_mode');
      await prefs.remove('pending_add_call_type');
      await prefs.remove('flutter.pending_add_phone');
      await prefs.remove('flutter.pending_add_mode');
      await prefs.remove('flutter.pending_add_call_type');
    } catch (_) {}
    try {
      const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
      await ch.invokeMethod('clearPendingAddPhone');
    } catch (_) {}
  }

  double? get _parsedAmount {
    final t = _amount.text.trim().replaceAll(',', '').replaceAll('،', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = Customer.normalizePhone(_phone.text.trim());
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نام و شماره الزامی است')));
      return;
    }
    if (phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شماره معتبر نیست')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.editCustomer == null) {
        final count = (await _service.getAll()).length;
        final existing = await _service.findByPhone(phone);
        if (existing == null && !await LicenseService.instance.canAddCustomer(count)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('سقف رایگان ۱۰۰ مشتری پر شد. نسخه پرو را فعال کنید.')),
            );
          }
          return;
        }
      }
      if (widget.editCustomer != null) {
        final updated = widget.editCustomer!.copyWith(
          name: name,
          phone: phone,
          note: _note.text.trim(),
          tag: _tag,
          status: _status,
          city: _city.text.trim().isEmpty ? null : _city.text.trim(),
          orderAmount: _parsedAmount,
          reminderAt: _reminderAt,
          clearReminder: _reminderAt == null,
        );
        // copyWith with null city might keep old - force via direct if needed
        final fixed = Customer(
          id: updated.id,
          name: name,
          phone: phone,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          tag: _tag,
          status: _status,
          city: _city.text.trim().isEmpty ? null : _city.text.trim(),
          orderAmount: _parsedAmount,
          reminderAt: _reminderAt,
          favorite: updated.favorite,
          callCount: updated.callCount,
          firstCallAt: updated.firstCallAt,
          lastCallAt: updated.lastCallAt,
          createdAt: updated.createdAt,
        );
        await _service.update(fixed);
        await _clearPending();
        if (mounted) Navigator.pop(context, fixed);
      } else {
        final existing = await _service.findByPhone(phone);
        if (existing != null) {
          final fixed = Customer(
            id: existing.id,
            name: name,
            phone: phone,
            note: _note.text.trim().isEmpty ? existing.note : _note.text.trim(),
            tag: _tag,
            status: _status,
            city: _city.text.trim().isEmpty ? existing.city : _city.text.trim(),
            orderAmount: _parsedAmount ?? existing.orderAmount,
            reminderAt: _reminderAt ?? existing.reminderAt,
            favorite: existing.favorite,
            callCount: existing.callCount,
            firstCallAt: existing.firstCallAt,
            lastCallAt: existing.lastCallAt,
            createdAt: existing.createdAt,
          );
          await _service.update(fixed);
          await _recordIfNeeded(phone, name);
          await _clearPending();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مشتری به‌روز شد')));
            Navigator.pop(context, fixed);
          }
        } else {
          final c = Customer(
            name: name,
            phone: phone,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            tag: _tag,
            status: _status,
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            orderAmount: _parsedAmount,
            reminderAt: _reminderAt,
          );
          final saved = await _service.add(c);
          await _recordIfNeeded(phone, name);
          await _clearPending();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مشتری و سابقه تماس ذخیره شد')));
            Navigator.pop(context, saved);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _appendTemplate(String t) {
    final cur = _note.text.trim();
    if (cur.isEmpty) {
      _note.text = t;
    } else if (!cur.contains(t)) {
      _note.text = '$cur\n$t';
    }
    _note.selection = TextSelection.fromPosition(TextPosition(offset: _note.text.length));
    setState(() {});
  }

  void _setReminder(int days) {
    final now = DateTime.now();
    setState(() {
      _reminderAt = DateTime(now.year, now.month, now.day).add(Duration(days: days));
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editCustomer != null;
    final fromCall = widget.initialPhone != null && !editing;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'ویرایش مشتری' : (fromCall ? 'ذخیره بعد از تماس' : 'مشتری جدید'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (fromCall)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'شماره جدید — وضعیت، یادداشت و یادآوری را همین‌جا کامل کنید',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'نام', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'شماره موبایل', prefixIcon: Icon(Icons.phone_outlined)),
          ),
          const SizedBox(height: 16),
          Text('دسته‌بندی', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['مشتری', 'همکار', 'سایر'].map((t) {
              final sel = _tag == t;
              return ChoiceChip(
                label: Text(t),
                selected: sel,
                onSelected: (_) => setState(() => _tag = t),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text('وضعیت فروش', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CustomerStatus.all.map((s) {
              final sel = _status == s;
              return ChoiceChip(
                label: Text(s),
                selected: sel,
                onSelected: (_) => setState(() => _status = s),
                selectedColor: Color(CustomerStatus.colorValue(s)),
                labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text('یادداشت‌های آماده', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_templates.isEmpty)
            Text('از تنظیمات → یادداشت‌های آماده اضافه کنید', style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _templates.map((t) {
                return ActionChip(
                  label: Text(t, style: const TextStyle(fontSize: 13)),
                  onPressed: () => _appendTemplate(t),
                  backgroundColor: AppColors.surfaceElevated,
                );
              }).toList(),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'یادداشت',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Text('شهر / منطقه', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _city,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'مثلاً تهران، کرج...'),
          ),
          const SizedBox(height: 16),
          Text('مبلغ سفارش (تومان)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'مثلاً 8500000'),
          ),
          const SizedBox(height: 16),
          Text('یادآوری تماس مجدد', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.schedule, size: 16),
                label: const Text('فردا'),
                onPressed: () => _setReminder(1),
              ),
              ActionChip(
                avatar: const Icon(Icons.schedule, size: 16),
                label: const Text('۳ روز بعد'),
                onPressed: () => _setReminder(3),
              ),
              ActionChip(
                avatar: const Icon(Icons.schedule, size: 16),
                label: const Text('یک هفته'),
                onPressed: () => _setReminder(7),
              ),
              if (_reminderAt != null)
                ActionChip(
                  label: Text('حذف یادآوری'),
                  onPressed: () => setState(() => _reminderAt = null),
                ),
            ],
          ),
          if (_reminderAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'یادآوری: ${_reminderAt!.year}/${_reminderAt!.month.toString().padLeft(2, '0')}/${_reminderAt!.day.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(editing ? 'ذخیره تغییرات' : 'افزودن به دفترچه'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
