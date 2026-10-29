import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:customer_callbook/core/theme/app_theme.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/core/theme/tag_colors.dart';
import 'package:customer_callbook/data/services/contact_cache.dart';
import 'package:customer_callbook/features/home/presentation/pages/home_page.dart';
import 'package:customer_callbook/services/call_listener_service.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/data/services/note_templates_service.dart';
import 'package:customer_callbook/services/reminder_service.dart';
import 'package:customer_callbook/services/widget_service.dart';

class CustomerCallbookApp extends StatefulWidget {
  const CustomerCallbookApp({super.key});

  @override
  State<CustomerCallbookApp> createState() => _CustomerCallbookAppState();
}

class _CustomerCallbookAppState extends State<CustomerCallbookApp> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    AppColors.isDark = false;
    await TagColors.instance.load();
    ContactCache.instance.warmUp();
    await CallListenerService.instance.initNotifications();
    CallListenerService.instance.restoreIfEnabled();
    try {
      await CustomerService().migrateTextEncoding();
      await NoteTemplatesService.instance.getAll(); // auto-repairs templates
    } catch (_) {}
    await ReminderService.instance.init();
    try {
      final all = await CustomerService().getAll();
      for (final c in all) {
        if (c.reminderAt != null) await ReminderService.instance.schedule(c);
      }
    } catch (_) {}
    WidgetService.instance.update();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    AppColors.isDark = false;
    return MaterialApp(
      title: 'فروشیار',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      home: const HomePage(),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
