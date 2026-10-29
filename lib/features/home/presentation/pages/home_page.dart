import 'package:customer_callbook/data/services/license_service.dart';
import 'package:customer_callbook/data/services/license_service.dart';
import 'package:customer_callbook/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:customer_callbook/features/reminders/presentation/pages/reminders_page.dart';
import 'package:customer_callbook/shared/widgets/customer_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/core/theme/theme_controller.dart';
import 'package:customer_callbook/core/theme/tag_colors.dart';
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/core/utils/jalali.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/features/phonebook/presentation/pages/phonebook_page.dart';
import 'package:customer_callbook/features/customer_detail/presentation/pages/customer_detail_page.dart';
import 'package:customer_callbook/features/call_sync/presentation/pages/call_sync_page.dart';
import 'package:customer_callbook/features/add_customer/presentation/pages/add_customer_page.dart';
import 'package:customer_callbook/features/history/presentation/pages/history_page.dart';
import 'package:customer_callbook/services/call_listener_service.dart';
import 'package:customer_callbook/data/services/note_templates_service.dart';
import 'package:customer_callbook/data/services/backup_service.dart';
import 'package:customer_callbook/features/report/presentation/pages/weekly_report_page.dart';
import 'package:customer_callbook/services/widget_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showOnboarding = false;
  bool _bootChecked = false;
  int _remindDue = 0;

  int _tab = 0;
  int _refreshToken = 0;
  final _service = CustomerService();
  List<Customer> _customers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    WidgetsBinding.instance.addPostFrameCallback((_) async { await _checkPendingStatus(); await _checkPendingAdd(); });
    _load();
  }


  Future<void> _checkOnboarding() async {
    final p = await SharedPreferences.getInstance();
    final done = p.getBool('onboarding_done_v1') ?? false;
    if (mounted) setState(() {
      _showOnboarding = !done;
      _bootChecked = true;
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.getAll();
    final due = await _service.remindersDueToday();
    WidgetService.instance.update();
    if (mounted) {
      setState(() {
        _customers = list;
        _remindDue = due.length;
        _loading = false;
        _refreshToken++;
      });
    }
  }

  /// شناسایی تماس‌های اخیر برای مشتریان ثبت‌شده (بدون درخواست مجوز اضافه)
  Future<void> _autoImportRecent() async {
    try {
      final entries = await _service.fetchRecentDeviceCalls(days: 2, limit: 25);
      final seen = <String>{};
      for (final e in entries) {
        final phone = (e['number'] ?? '').toString().trim();
        if (phone.isEmpty) continue;
        final key = Customer.normalizePhone(phone);
        if (seen.contains(key)) continue;
        seen.add(key);
        final existing = await _service.findByPhone(phone);
        if (existing == null) continue;
        final typ = (e['type'] ?? '').toString().toLowerCase();
        final typeInt = typ.contains('miss') || typ.contains('reject')
            ? 3
            : (typ.contains('in') ? 1 : 2);
        final ts = e['timestamp'];
        final at = ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
        // اگر آخرین تماس اپ جدیدتر/برابر است، رد شو
        if (existing.lastCallAt != null && at != null && !at.isAfter(existing.lastCallAt!)) {
          continue;
        }
        await _service.recordCall(phone, name: existing.name, type: typeInt);
        if (at != null) {
          await _service.addCallRecord(phone: phone, customerId: existing.id, type: typeInt, at: at);
        }
      }
    } catch (_) {}
  }

  Future<void> _dial(String phone) async {
    final uri = Uri(scheme: 'tel', path: Customer.normalizePhone(phone));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      await _service.recordCall(phone);
      _load();
    }
  }

    int get _todayCount {
    // فقط تماس‌هایی که از خود اپ زده/ثبت شده‌اند (lastCallAt + callCount>0)
    final now = DateTime.now();
    return _customers.where((c) {
      if (c.callCount <= 0) return false;
      final d = c.lastCallAt;
      if (d == null) return false;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  
  
  Future<void> _requestOverlay() async {
    try {
      const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
      await ch.invokeMethod('openOverlayPermission');
    } catch (_) {
      await openAppSettings();
    }
  }


  Future<void> _checkPendingStatus() async {
    try {
      final p = await SharedPreferences.getInstance();
      final phone = p.getString('pending_status_phone') ?? p.getString('flutter.pending_status_phone');
      final status = p.getString('pending_status_value') ?? p.getString('flutter.pending_status_value');
      await p.remove('pending_status_phone');
      await p.remove('pending_status_value');
      await p.remove('flutter.pending_status_phone');
      await p.remove('flutter.pending_status_value');
      if (phone == null || status == null || phone.isEmpty) return;
      final c = await _service.findByPhone(phone);
      if (c == null) return;
      final normalized = CustomerStatus.normalize(status);
      await _service.update(c.copyWith(status: normalized));
      await _service.updateLatestCallStatus(phone, normalized);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('وضعیت «${c.name}» → $normalized')),
        );
        _load();
      }
    } catch (_) {}
  }

  Future<void> _checkPendingAdd() async {
    try {
      String? n;
      var callType = 1;
      try {
        const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
        n = await ch.invokeMethod<String>('getPendingAddPhone');
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      if (n == null || n.isEmpty) {
        n = prefs.getString('pending_add_phone') ?? prefs.getString('flutter.pending_add_phone');
      }
      final typeStr = prefs.getString('pending_add_call_type') ??
          prefs.getString('flutter.pending_add_call_type') ??
          '1';
      callType = int.tryParse(typeStr) ?? 1;
      if (n != null && n.isNotEmpty) {
        await prefs.remove('pending_add_phone');
        await prefs.remove('pending_add_mode');
        await prefs.remove('pending_add_call_type');
        await prefs.remove('flutter.pending_add_phone');
        await prefs.remove('flutter.pending_add_mode');
        await prefs.remove('flutter.pending_add_call_type');
      }
      if (n == null || n.isEmpty || !mounted) return;
      final existing = await _service.findByPhone(n);
      if (existing != null) {
        try {
          const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
          await ch.invokeMethod('clearPendingAddPhone');
        } catch (_) {}
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddCustomerPage(initialPhone: n, fromCall: true, callType: callType),
        ),
      );
      _load();
    } catch (_) {}
  }

  
  Future<void> _openOverlayPermission() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }

    @override
  Widget build(BuildContext context) {
    if (!_bootChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showOnboarding) {
      return OnboardingPage(onDone: () {
        setState(() => _showOnboarding = false);
        _load();
      });
    }
  return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.background, AppColors.backgroundEnd],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: [
              _CallsTab(
                customers: _customers,
                loading: _loading,
                todayCount: _todayCount,
                remindDue: _remindDue,
                onRefresh: _load,
                onDial: _dial,
                onOpenDetail: (c) async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: c)));
                  _load();
                },
                onSync: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const CallSyncPage()));
                  _load();
                },
                onReminders: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const RemindersPage()));
                  _load();
                },
              ),
              PhonebookPage(onChanged: _load, refreshToken: _refreshToken),
              HistoryPage(refreshToken: _refreshToken),
              _SettingsTab(onReload: _load, customers: _customers),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppColors.navBar,
            boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) {
              setState(() {
                _tab = i;
                if (i == 1 || i == 2) _refreshToken++;
              });
              if (i == 1 || i == 2) _load();
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.phone_outlined), activeIcon: Icon(Icons.phone_rounded), label: 'تماس‌ها'),
              BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people_rounded), label: 'مشتریان'),
              BottomNavigationBarItem(icon: Icon(Icons.history_outlined), activeIcon: Icon(Icons.history_rounded), label: 'سابقه'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings_rounded), label: 'تنظیمات'),
            ],
          ),
        ),
        floatingActionButton: _tab == 1
            ? FloatingActionButton(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerPage()));
                  _load();
                },
                child: const Icon(Icons.person_add_alt_1_rounded),
              )
            : null,
      ),
    );
  }
}


class _CallsHeaderClock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final j = Jalali.toJalali(now);
    final dayName = Jalali.weekdayName(now);
    final dateStr = '${j[0]}/${j[1].toString().padLeft(2, '0')}/${j[2].toString().padLeft(2, '0')}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تماس‌ها', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                '$dayName  ·  $dateStr',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                Jalali.clock(now),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CallsTab extends StatelessWidget {
  final List<Customer> customers;
  final bool loading;
  final int todayCount;
  final int remindDue;
  final VoidCallback onRefresh;
  final Future<void> Function(String) onDial;
  final Future<void> Function(Customer) onOpenDetail;
  final Future<void> Function() onSync;
  final Future<void> Function() onReminders;

  const _CallsTab({
    required this.customers,
    required this.loading,
    required this.todayCount,
    required this.remindDue,
    required this.onRefresh,
    required this.onDial,
    required this.onOpenDetail,
    required this.onSync,
    required this.onReminders,
  });

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    return Jalali.timeAgoOrJalali(dt);
  }

  Color _avatarColor(String name) {
    final p = AppColors.avatarPalette;
    return p[name.hashCode.abs() % p.length];
  }

  @override
  Widget build(BuildContext context) {
    final recent = customers.where((c) => c.lastCallAt != null && c.callCount > 0).toList()
      ..sort((a, b) => b.lastCallAt!.compareTo(a.lastCallAt!));

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CallsHeaderClock(),
                  const SizedBox(height: 18),
                  // چهار کارت هم‌اندازه و رنگی
                  Row(
                    children: [
                      Expanded(
                        child: _FeatureTile(
                          title: 'یادآوری تماس',
                          subtitle: remindDue == 0 ? 'برای امروز ندارید' : '$remindDue مورد پیگیری',
                          icon: Icons.alarm_rounded,
                          color: const Color(0xFFF59E0B),
                          badge: remindDue > 0 ? '$remindDue' : null,
                          onTap: onReminders,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FeatureTile(
                          title: 'همگام گوشی',
                          subtitle: 'دریافت از گوشی',
                          icon: Icons.phone_android_rounded,
                          color: const Color(0xFF6366F1),
                          onTap: onSync,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _FeatureTile(
                          title: 'مشتریان',
                          subtitle: '${customers.length} نفر',
                          icon: Icons.people_alt_rounded,
                          color: const Color(0xFF8B5CF6),
                          value: '${customers.length}',
                          onTap: null,
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FeatureTile(
                          title: 'تماس امروز',
                          subtitle: '$todayCount تماس',
                          icon: Icons.phone_in_talk_rounded,
                          color: const Color(0xFF10B981),
                          value: '$todayCount',
                          onTap: null,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Icon(Icons.history_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text('آخرین تماس‌ها', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          if (loading)
            const _SliverLoading()
          else if (recent.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_disabled_rounded, size: 48, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text('هنوز تماسی ثبت نشده', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final c = recent[i];
                    final tagColor = TagColors.instance.of(c.tag);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _GlassCard(
                        onTap: () => onDial(c.phone),
                        onLongPress: () => onOpenDetail(c),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.info_outline_rounded, size: 20, color: AppColors.textMuted),
                              onPressed: () => onOpenDetail(c),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                                  Text(
                                    Customer.displayPhone(c.phone),
                                    style: Theme.of(context).textTheme.bodySmall,
                                    textDirection: TextDirection.ltr,
                                  ),
                                  Text(_timeAgo(c.lastCallAt), style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            CustomerAvatar(name: c.name, tag: c.tag, favorite: c.favorite, size: 44),
                            const SizedBox(width: 4),
                            Container(
                              width: 4,
                              height: 36,
                              decoration: BoxDecoration(color: tagColor, borderRadius: BorderRadius.circular(4)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: recent.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SliverLoading extends StatelessWidget {
  const _SliverLoading();
  @override
  Widget build(BuildContext context) => SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppColors.primary)));
}

class _FeatureTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? badge;
  final String? value;
  final VoidCallback? onTap;
  final bool compact;

  const _FeatureTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.badge,
    this.value,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: compact ? 88 : 108),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(10)),
                  child: Text(badge!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                )
              else if (value != null)
                Text(value!, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color))
              else
                Icon(Icons.chevron_left_rounded, color: color.withOpacity(0.5), size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.2, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: body),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  const _StatCard({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _PrimaryAction({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
            ),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: Colors.white.withOpacity(0.9)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const _GlassCard({required this.child, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(20),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: child),
        ),
      ),
    );
  }
}

class _GlowIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _GlowIcon(this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}


class _SettingsTab extends StatefulWidget {
  final VoidCallback onReload;
  final List<Customer> customers;
  const _SettingsTab({required this.onReload, required this.customers});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _resultPopup = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _resultPopup = p.getBool('show_result_popup') ?? true;
      });
    }
  }

  Future<void> _setResultPopup(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('show_result_popup', v);
    setState(() => _resultPopup = v);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تنظیمات', style: Theme.of(context).textTheme.headlineMedium),
                  Text('مدیریت تنظیمات و امکانات برنامه', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.settings_rounded, color: AppColors.primary, size: 26),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // پاپ‌آپ نتیجه — فشرده
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('پاپ‌آپ نتیجه تماس', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              _resultPopup ? 'فعال — بعد از قطع تماس' : 'خاموش',
              style: TextStyle(fontSize: 12, color: _resultPopup ? AppColors.accent : AppColors.textMuted),
            ),
            value: _resultPopup,
            activeColor: AppColors.primary,
            onChanged: (v) async {
              await _setResultPopup(v);
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(height: 10),
        const _CallDetectTile(),

        const SizedBox(height: 20),
        _sectionLabel(context, 'مجوزها'),
        _groupCard([
          _nav(context, Icons.shield_rounded, const Color(0xFF3B82F6), 'مرکز مجوزها',
              'مجوزها + آموزش فعال‌سازی', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const _PermissionsHubPage()));
          }),
        ]),

        const SizedBox(height: 18),
        _sectionLabel(context, 'تنظیمات اپ'),
        _groupCard([
          _nav(context, Icons.phone_android_rounded, AppColors.primary, 'تماس‌های گوشی',
              'دریافت تاریخچه و افزودن به مشتریان', () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CallSyncPage()));
            widget.onReload();
          }),
          _nav(context, Icons.palette_rounded, AppColors.warning, 'رنگ دسته‌بندی‌ها',
              'رنگ گروه‌های مشتریان', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const _TagColorPage()));
          }),
          _nav(context, Icons.sticky_note_2_rounded, const Color(0xFF38BDF8), 'یادداشت آماده',
              'مدیریت یادداشت‌های سریع', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const _NoteTemplatesPage()));
          }),
        ]),

        const SizedBox(height: 18),
        _sectionLabel(context, 'امکانات'),
        _groupCard([
          _nav(context, Icons.event_note_rounded, const Color(0xFF10B981), 'امروز زنگ بزن',
              'یادآوری تماس امروز و آینده', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const RemindersPage()));
          }),
          _nav(context, Icons.insights_rounded, const Color(0xFF8B5CF6), 'گزارش هفتگی',
              'آمار تماس و وضعیت فروش', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyReportPage()));
          }),
          _nav(context, Icons.backup_rounded, const Color(0xFF34D399), 'پشتیبان شماره‌ها',
              'ذخیره و بازیابی بعد از نصب مجدد', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => _BackupPage(onDone: widget.onReload)));
          }),
          _nav(context, Icons.upload_file_rounded, const Color(0xFFA78BFA), 'خروجی لیست مشتریان',
              'ذخیره CSV در پوشه دانلود', () async {
            try {
              final csv = await BackupService.instance.exportCsv();
              const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
              final path = await ch.invokeMethod<String>('saveToDownloads', {
                'content': csv,
                'fileName': 'customers_export.csv',
              });
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(path != null ? 'ذخیره شد: $path' : 'ذخیره شد')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
              }
            }
          }),
        ]),

        const SizedBox(height: 18),
        _sectionLabel(context, 'اطلاعات برنامه'),
        _groupCard([
          _nav(context, Icons.info_rounded, AppColors.textMuted, 'درباره برنامه',
              'نسخه و پشتیبانی', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const _AboutPage()));
          }),
        ]),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
      )),
    );
  }

  Widget _groupCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, indent: 64, color: AppColors.border.withOpacity(0.6)),
          ],
        ],
      ),
    );
  }

  Widget _nav(BuildContext context, IconData icon, Color color, String title, String sub, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Icon(Icons.chevron_left_rounded, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}

class _TagColorPage extends StatefulWidget {
  const _TagColorPage();
  @override
  State<_TagColorPage> createState() => _TagColorPageState();
}

class _TagColorPageState extends State<_TagColorPage> {
  @override
  Widget build(BuildContext context) {
    final tags = TagColors.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('رنگ دسته‌بندی‌ها')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: ['مشتری', 'همکار', 'سایر'].map((tag) {
          final color = tags.of(tag);
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(width: 16, height: 16, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(tag, style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: tags.palette.map((c) {
                      final selected = TagColors.instance.isSelected(tag, c);
                      return GestureDetector(
                        onTap: () async {
                          await tags.set(tag, c);
                          setState(() {});
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: selected ? Border.all(color: Colors.white, width: 3) : null,
                            boxShadow: [BoxShadow(color: c.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
                          ),
                          child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CallDetectTile extends StatefulWidget {
  const _CallDetectTile();
  @override
  State<_CallDetectTile> createState() => _CallDetectTileState();
}

class _CallDetectTileState extends State<_CallDetectTile> {
  bool _on = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    CallListenerService.instance.isEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    try {
      if (v) {
        final ok = await CallListenerService.instance.enableAndStart();
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('مجوز تلفن لازم است. از تنظیمات مجوز بدهید.')),
          );
          await openAppSettings();
        } else if (ok && mounted) {
          try {
            const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
            final can = await ch.invokeMethod<bool>('canDrawOverlays') ?? false;
            if (!can) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('برای پاپ‌آپ روی صفحه تماس، مجوز «نمایش روی سایر برنامه‌ها» را بدهید')),
              );
              await ch.invokeMethod('openOverlayPermission');
            }
          } catch (_) {}
        }
        setState(() => _on = ok);
      } else {
        await CallListenerService.instance.disableAndStop();
        setState(() => _on = false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        children: [
          if (_busy)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(value: _on, onChanged: _toggle),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('شناسایی تماس ورودی', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  _on ? 'فعال — با تماس، اعلان نام مشتری می‌آید' : 'خاموش — برای اعلان هنگام تماس روشن کنید',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [AppColors.accent, AppColors.accent.withOpacity(0.75)]),
              boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.ring_volume_rounded, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}


class _NoteTemplatesPage extends StatefulWidget {
  const _NoteTemplatesPage();
  @override
  State<_NoteTemplatesPage> createState() => _NoteTemplatesPageState();
}

class _NoteTemplatesPageState extends State<_NoteTemplatesPage> {
  List<String> _items = [];
  final _ctrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await NoteTemplatesService.instance.getAll();
    if (mounted) setState(() { _items = list; _loading = false; });
  }

  Future<void> _add() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    await NoteTemplatesService.instance.add(text);
    _ctrl.clear();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('«$text» اضافه شد')));
    }
  }

  Future<void> _remove(String text) async {
    await NoteTemplatesService.instance.remove(text);
    await _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('یادداشت‌های آماده')),
      body: Column(
        children: [
          // ساخت یادداشت — همیشه بالای صفحه
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            color: AppColors.surfaceElevated,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ساخت یادداشت جدید', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'مثلاً: ارسال فاکتور',
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.add_circle, color: AppColors.primary, size: 28),
                      onPressed: _add,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن یادداشت'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(child: Text('هنوز یادداشتی نیست — بالا بسازید', style: Theme.of(context).textTheme.bodyMedium))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final e = _items[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(e),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline, color: AppColors.danger),
                                onPressed: () => _remove(e),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}


class _BackupPage extends StatefulWidget {
  final VoidCallback? onDone;
  const _BackupPage({this.onDone});
  @override
  State<_BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<_BackupPage> {
  bool _busy = false;
  String? _msg;

  Future<void> _saveFile() async {
    setState(() { _busy = true; _msg = null; });
    try {
      final json = await BackupService.instance.exportJson();
      const channel = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
      String? path;
      try {
        path = await channel.invokeMethod<String>('saveToDownloads', {
          'content': json,
          'fileName': 'daftarche_backup.json',
        });
      } catch (_) {
        path = await channel.invokeMethod<String>('saveBackupFile', {
          'content': json,
          'name': 'daftarche_backup.json',
        });
      }
      if (mounted) {
        setState(() => _msg =
            '✓ ذخیره مستقیم انجام شد\n'
            '📁 فایل‌ها → Download → Daftarche\n'
            '📄 daftarche_backup.json\n'
            '${path != null ? 'مسیر: $path' : ''}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('پشتیبان در Download/Daftarche ذخیره شد')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _msg = 'خطا در ذخیره مستقیم: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadFile() async {
    setState(() { _busy = true; _msg = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() { _busy = false; _msg = 'فایلی انتخاب نشد'; });
        return;
      }
      final f = result.files.first;
      String raw;
      if (f.bytes != null) {
        raw = String.fromCharCodes(f.bytes!);
      } else if (f.path != null) {
        raw = await File(f.path!).readAsString();
      } else {
        throw Exception('نتوانست فایل را بخواند');
      }
      final n = await BackupService.instance.importJson(raw);
      widget.onDone?.call();
      if (mounted) {
        setState(() => _msg = '✓ $n مشتری از فایل بازیابی شد');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$n مشتری بازیابی شد'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _msg = 'خطا در بازیابی: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پشتیبان شماره‌ها')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'ذخیره مستقیم (بدون اشتراک‌گذاری):\n'
              '📂 فایل‌ها → Download → Daftarche\n'
              '📄 daftarche_backup.json\n\n'
              '۱) ذخیره فایل پشتیبان را بزنید\n'
              '۲) بعد از نصب مجدد، انتخاب فایل و همین مسیر را باز کنید',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          Text('ذخیره', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _saveFile,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('ذخیره فایل پشتیبان'),
            ),
          ),
          const SizedBox(height: 28),
          Text('بازیابی', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _loadFile,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('انتخاب فایل پشتیبان از گوشی'),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_msg != null) ...[
            const SizedBox(height: 20),
            Text(_msg!, style: TextStyle(color: AppColors.primary, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('درباره برنامه')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Icon(Icons.contacts_rounded, size: 64, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('فروشیار', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('نسخه ۱.۳۸.۳ · ${LicenseService.isPersonalBuild ? 'شخصی' : 'بازار'}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          ListTile(
            leading: Icon(Icons.email_outlined, color: AppColors.primary),
            title: const Text('پشتیبانی و توسعه'),
            subtitle: const Text('info@apadanasleep.ir'),
            onTap: () async {
              final uri = Uri(scheme: 'mailto', path: 'info@apadanasleep.ir', queryParameters: {
                'subject': 'فروشیار',
              });
              // ignore: deprecated_member_use
              try {
                await launchUrl(uri);
              } catch (_) {}
            },
          ),
          const SizedBox(height: 8),
          Text(
            'آپادانا اسلیپ',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}


class _PermissionsHubPage extends StatelessWidget {
  const _PermissionsHubPage();

  Future<void> _openOverlay() async {
    try {
      const ch = MethodChannel('ir.apadanasleep.customer_callbook/call_log');
      await ch.invokeMethod('openOverlayPermission');
    } catch (_) {
      await openAppSettings();
    }
  }

  Widget _row(IconData icon, Color color, String title, String sub, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E).withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('تنظیم', style: TextStyle(color: Color(0xFF16A34A), fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مرکز مجوزها')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('دسترسی‌های مورد نیاز برای عملکرد صحیح برنامه', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _row(Icons.phone_in_talk_rounded, const Color(0xFF22C55E), 'تلفن و گزارش تماس', 'خواندن تاریخچه تماس‌ها', () => openAppSettings()),
                Divider(height: 1, indent: 64, color: AppColors.border),
                _row(Icons.contacts_rounded, const Color(0xFF8B5CF6), 'نمایش نام مخاطبین گوشی', 'نمایش نام هنگام تماس', () => openAppSettings()),
                Divider(height: 1, indent: 64, color: AppColors.border),
                _row(Icons.notifications_active_rounded, const Color(0xFF3B82F6), 'اعلان‌ها', 'اعلان تماس و یادآوری', () => openAppSettings()),
                Divider(height: 1, indent: 64, color: AppColors.border),
                _row(Icons.layers_rounded, const Color(0xFFEF4444), 'پاپ‌آپ', 'نمایش روی سایر برنامه‌ها', _openOverlay),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'برای استفاده کامل، همه مجوزها را فعال کنید. در هواوی/شیائومی: باتری بدون محدودیت + راه‌اندازی خودکار.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OnboardingPage(onDone: () => Navigator.pop(context)),
                  ),
                );
              },
              icon: const Icon(Icons.school_rounded),
              label: const Text('آموزش فعال‌سازی گام‌به‌گام'),
            ),
          ),
        ],
      ),
    );
  }
}
