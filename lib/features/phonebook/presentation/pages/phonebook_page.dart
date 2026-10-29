import 'package:flutter/services.dart';
import 'package:customer_callbook/shared/widgets/customer_avatar.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/core/theme/tag_colors.dart';
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/features/customer_detail/presentation/pages/customer_detail_page.dart';
import 'package:customer_callbook/features/add_customer/presentation/pages/add_customer_page.dart';

class PhonebookPage extends StatefulWidget {
  final VoidCallback? onChanged;
  final int refreshToken;
  const PhonebookPage({super.key, this.onChanged, this.refreshToken = 0});

  @override
  State<PhonebookPage> createState() => _PhonebookPageState();
}

class _PhonebookPageState extends State<PhonebookPage> {
  final _service = CustomerService();
  final _search = TextEditingController();
  List<Customer> _all = [];
  List<Customer> _filtered = [];
  String _tag = 'همه';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PhonebookPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.getAll();
    if (mounted) {
      setState(() {
        _all = list;
        _loading = false;
      });
      _apply();
    }
  }

  void _apply() {
    var list = List<Customer>.from(_all);
    if (_tag == 'ویژه') {
      list = list.where((c) => c.favorite).toList();
    } else if (_tag == 'یادآوری') {
      list = list.where((c) => c.reminderAt != null).toList();
    } else if (CustomerStatus.all.contains(_tag)) {
      list = list.where((c) => c.status == _tag).toList();
    } else if (_tag != 'همه') {
      list = list.where((c) => c.tag == _tag).toList();
    }
    final q = _search.text.trim();
    if (q.isNotEmpty) {
      final lower = q.toLowerCase();
      list = list.where((c) {
        return c.name.toLowerCase().contains(lower) ||
            c.phone.contains(q) ||
            Customer.normalizePhone(c.phone).contains(Customer.normalizePhone(q)) ||
            (c.city ?? '').toLowerCase().contains(lower) ||
            (c.note ?? '').toLowerCase().contains(lower);
      }).toList();
    }
    setState(() => _filtered = list);
  }

  Future<void> _dial(String phone) async {
    final uri = Uri(scheme: 'tel', path: Customer.normalizePhone(phone));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      await _service.recordCall(phone);
      _load();
      widget.onChanged?.call();
    }
  }

  Color _avatarColor(String name) {
    final colors = AppColors.avatarPalette;
    return colors[name.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('مشتریان', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('دفترچه مخاطبین کسب‌وکار', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                onChanged: (_) => _apply(),
                decoration: const InputDecoration(
                  hintText: 'نام، شماره، شهر، یادداشت...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['همه', 'ویژه', 'یادآوری', 'جدید', 'در حال مذاکره', 'خرید کرده', 'بی‌پاسخ', 'مشتری', 'همکار', 'سایر'].map((t) {
                    final sel = _tag == t;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(t),
                        selected: sel,
                        onSelected: (_) {
                          setState(() => _tag = t);
                          _apply();
                        },
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: sel ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: sel ? AppColors.primary : AppColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_off_outlined, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text('مشتری‌ای نیست', style: Theme.of(context).textTheme.bodyMedium),
                          TextButton(
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerPage()));
                              _load();
                              widget.onChanged?.call();
                            },
                            child: const Text('افزودن مشتری'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final c = _filtered[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: const Offset(0, 5))],
                            ),
                            child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: c)),
                                );
                                _load();
                                widget.onChanged?.call();
                              },
                              onLongPress: () async {
                                await Clipboard.setData(ClipboardData(text: Customer.normalizePhone(c.phone)));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('شماره کپی شد'), duration: Duration(seconds: 1)),
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    // دکمه تماس سریع
                                    IconButton(
                                      onPressed: () => _dial(c.phone),
                                      icon: Icon(Icons.phone, color: AppColors.accent),
                                      style: IconButton.styleFrom(backgroundColor: AppColors.accent.withOpacity(0.12)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              if (c.favorite) Icon(Icons.star, size: 14, color: AppColors.warning),
                                              if (c.favorite) const SizedBox(width: 4),
                                              Flexible(child: Text(c.name, style: Theme.of(context).textTheme.titleMedium)),
                                            ],
                                          ),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: TagColors.instance.of(c.tag).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(c.tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TagColors.instance.of(c.tag))),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(Customer.phoneTypeLabel(c.phone), style: Theme.of(context).textTheme.bodySmall),
                                            ],
                                          ),
                                          Text(
                                            Customer.displayPhone(c.phone),
                                            style: Theme.of(context).textTheme.bodySmall,
                                            textDirection: TextDirection.ltr,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    CustomerAvatar(name: c.name, tag: c.tag, favorite: c.favorite, size: 48),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}