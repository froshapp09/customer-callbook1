import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/data/services/customer_service.dart';
import 'package:customer_callbook/data/services/note_templates_service.dart';

class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  final _customers = CustomerService();

  Future<String> exportJson() async {
    final list = await _customers.getAll();
    final templates = await NoteTemplatesService.instance.getAll();
    final map = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'customers': list.map((c) => c.toJson()).toList(),
      'noteTemplates': templates,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  Future<String> exportCsv() async {
    final list = await _customers.getAll();
    final buf = StringBuffer('name,phone,tag,status,city,note,callCount,favorite,orderAmount\n');
    for (final c in list) {
      final note = (c.note ?? '').replaceAll('"', '""').replaceAll('\n', ' ');
      final city = (c.city ?? '').replaceAll('"', '""');
      buf.writeln('"${c.name}","${c.phone}","${c.tag}","${c.status}","$city","$note",${c.callCount},${c.favorite},${c.orderAmount ?? ''}');
    }
    return buf.toString();
  }

  /// بازگردانی از JSON پشتیبان — شماره‌های تکراری به‌روز می‌شوند
  Future<int> importJson(String raw) async {
    final data = jsonDecode(raw);
    if (data is! Map) throw Exception('فرمت نامعتبر');
    final list = data['customers'];
    if (list is! List) throw Exception('لیست مشتری نیست');
    int n = 0;
    for (final e in list) {
      if (e is! Map) continue;
      final c = Customer.fromJson(Map<String, dynamic>.from(e));
      final existing = await _customers.findByPhone(c.phone);
      if (existing == null) {
        await _customers.add(c);
      } else {
        await _customers.update(Customer(
          id: existing.id,
          name: c.name.isNotEmpty ? c.name : existing.name,
          phone: existing.phone,
          note: c.note ?? existing.note,
          tag: c.tag,
          status: c.status,
          city: c.city ?? existing.city,
          orderAmount: c.orderAmount ?? existing.orderAmount,
          reminderAt: c.reminderAt ?? existing.reminderAt,
          favorite: c.favorite,
          callCount: existing.callCount > c.callCount ? existing.callCount : c.callCount,
          firstCallAt: existing.firstCallAt ?? c.firstCallAt,
          lastCallAt: existing.lastCallAt ?? c.lastCallAt,
          createdAt: existing.createdAt,
        ));
      }
      n++;
    }
    final tpls = data['noteTemplates'];
    if (tpls is List && tpls.isNotEmpty) {
      await NoteTemplatesService.instance.saveAll(tpls.map((e) => e.toString()).toList());
    }
    return n;
  }
}
