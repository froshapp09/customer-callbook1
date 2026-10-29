import 'package:customer_callbook/core/utils/text_repair.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:customer_callbook/data/models/customer.dart';

/// کش یک‌باره مخاطبین گوشی برای سرعت
class ContactCache {
  static final ContactCache instance = ContactCache._();
  ContactCache._();

  Map<String, String>? _phoneToName;
  bool _loading = false;

  Future<void> warmUp() async {
    if (_phoneToName != null || _loading) return;
    _loading = true;
    try {
      final ok = await FlutterContacts.requestPermission(readonly: true);
      if (!ok) {
        _phoneToName = {};
        return;
      }
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final map = <String, String>{};
      for (final c in contacts) {
        final name = TextRepair.fix(c.displayName.trim());
        if (name.isEmpty) continue;
        for (final p in c.phones) {
          final n = Customer.normalizePhone(p.number);
          if (n.isNotEmpty) map[n] = name;
        }
      }
      _phoneToName = map;
    } catch (_) {
      _phoneToName = {};
    } finally {
      _loading = false;
    }
  }

  Future<String?> lookup(String phone) async {
    await warmUp();
    return _phoneToName?[Customer.normalizePhone(phone)];
  }

  void invalidate() => _phoneToName = null;
}
