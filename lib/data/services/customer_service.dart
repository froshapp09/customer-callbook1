import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:customer_callbook/data/services/contact_cache.dart';
import 'package:customer_callbook/data/models/customer.dart';
import 'package:customer_callbook/data/models/call_record.dart';
import 'package:uuid/uuid.dart';
import 'package:customer_callbook/core/utils/text_repair.dart';

class CustomerService {
  static const _key = 'customers_v2';

  Future<List<Customer>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    var customers = list.map((e) => Customer.fromJson(Map<String, dynamic>.from(e))).toList();
    // تعمیر نام‌های خراب (mojibake)
    var changed = false;
    customers = customers.map((c) {
      final n = TextRepair.fix(c.name);
      final note = c.note != null ? TextRepair.fix(c.note!) : null;
      final city = c.city != null ? TextRepair.fix(c.city!) : null;
      if (n != c.name || note != c.note || city != c.city) {
        changed = true;
        return c.copyWith(name: n, note: note, city: city);
      }
      return c;
    }).toList();
    if (changed) {
      await _save(customers);
    }
    customers.sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        final aT = a.lastCallAt ?? a.createdAt;
        final bT = b.lastCallAt ?? b.createdAt;
        return bT.compareTo(aT);
      });
    return customers;
  }

  Future<void> _save(List<Customer> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<Customer> add(Customer c) async {
    final all = await getAll();
    // جلوگیری از تکراری
    final norm = Customer.normalizePhone(c.phone);
    final idx = all.indexWhere((e) => Customer.samePhone(e.phone, norm));
    if (idx >= 0) {
      final existing = all[idx];
      final updated = Customer(
        id: existing.id,
        name: c.name.isNotEmpty && c.name != c.phone ? c.name : existing.name,
        phone: existing.phone,
        note: (c.note != null && c.note!.isNotEmpty) ? c.note : existing.note,
        tag: c.tag.isNotEmpty ? c.tag : existing.tag,
        status: c.status.isNotEmpty ? c.status : existing.status,
        city: c.city ?? existing.city,
        orderAmount: c.orderAmount ?? existing.orderAmount,
        reminderAt: c.reminderAt ?? existing.reminderAt,
        favorite: c.favorite || existing.favorite,
        callCount: existing.callCount + (c.callCount > 0 ? c.callCount : 0),
        firstCallAt: existing.firstCallAt ?? c.firstCallAt,
        lastCallAt: c.lastCallAt ?? existing.lastCallAt,
        createdAt: existing.createdAt,
      );
      all[idx] = updated;
      await _save(all);
      return updated;
    }
    all.add(c);
    await _save(all);
    return c;
  }

  Future<void> update(Customer c) async {
    final all = await getAll();
    final i = all.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      all[i] = c;
      await _save(all);
    }
  }

  Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((e) => e.id == id);
    await _save(all);
  }

  Future<Customer?> findByPhone(String phone) async {
    final norm = Customer.normalizePhone(phone);
    final all = await getAll();
    try {
      return all.firstWhere((e) => Customer.samePhone(e.phone, norm));
    } catch (_) {
      return null;
    }
  }

  Future<Customer> recordCall(String phone, {String? name, int type = 2}) async {
    final existing = await findByPhone(phone);
    final now = DateTime.now();
    if (existing != null) {
      final updated = existing.copyWith(
        callCount: existing.callCount + 1,
        lastCallAt: now,
        firstCallAt: existing.firstCallAt ?? now,
        name: (name != null && name.isNotEmpty && !_isJunkName(name)) ? name : existing.name,
      );
      await update(updated);
      await addCallRecord(phone: phone, customerId: updated.id, type: type);
      return updated;
    }
    final resolved = await lookupNameFromDeviceContacts(phone);
    final finalName = (name != null && !_isJunkName(name))
        ? name
        : (resolved ?? phone);
    final c = Customer(
      name: finalName,
      phone: Customer.normalizePhone(phone),
      callCount: 1,
      firstCallAt: now,
      lastCallAt: now,
    );
    final saved = await add(c);
    await addCallRecord(phone: phone, customerId: saved.id, type: type);
    return saved;
  }

  /// نام‌های بی‌معنی اپراتور/سیستم را رد می‌کند
  static bool _isJunkName(String name) {
    final n = name.trim();
    if (n.isEmpty) return true;
    if (n.length < 2) return true;
    // مثل B.QMEHRIRAN یا فقط عدد
    if (RegExp(r'^[A-Z0-9.\-_+]+$').hasMatch(n) && !RegExp(r'[\u0600-\u06FF]').hasMatch(n)) {
      if (n.contains('.') || n.length > 12) return true;
    }
    if (RegExp(r'^\+?\d+$').hasMatch(n)) return true;
    return false;
  }

  Future<String?> lookupNameFromDeviceContacts(String phone) async {
    final name = await ContactCache.instance.lookup(phone);
    if (name != null && name.isNotEmpty && !_isJunkName(name)) return name;
    return null;
  }

  Future<List<Customer>> search(String q) async {
    final all = await getAll();
    if (q.trim().isEmpty) return all;
    final lower = q.trim().toLowerCase();
    final nq = Customer.normalizePhone(q);
    return all.where((c) {
      return c.name.toLowerCase().contains(lower) ||
          c.phone.contains(lower) ||
          Customer.normalizePhone(c.phone).contains(nq) ||
          (c.note ?? '').toLowerCase().contains(lower) ||
          (c.city ?? '').toLowerCase().contains(lower) ||
          c.tag.contains(lower) ||
          c.status.contains(lower);
    }).toList();
  }

  /// یادآوری‌های امروز و عقب‌افتاده (مقایسه روز تقویمی)
  Future<List<Customer>> remindersDueToday() async {
    final all = await getAll();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final list = all.where((c) {
      final r = c.reminderAt;
      if (r == null) return false;
      final rd = DateTime(r.year, r.month, r.day);
      return !rd.isAfter(today); // امروز یا قبل
    }).toList();
    list.sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
    return list;
  }

  /// یادآوری‌های ۷ روز آینده (به‌جز امروز که در due است)
  Future<List<Customer>> remindersUpcoming() async {
    final all = await getAll();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 8));
    final list = all.where((c) {
      final r = c.reminderAt;
      if (r == null) return false;
      final rd = DateTime(r.year, r.month, r.day);
      return rd.isAfter(today) && rd.isBefore(end);
    }).toList();
    list.sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
    return list;
  }

  static const _callsKey = 'call_records_v1';

  Future<List<CallRecord>> getCallHistory({String? phone, String? customerId, int limit = 50}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_callsKey);
    if (raw == null || raw.isEmpty) return [];
    var list = (jsonDecode(raw) as List)
        .map((e) => CallRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (phone != null) {
      final n = Customer.normalizePhone(phone);
      list = list.where((c) => Customer.normalizePhone(c.phone) == n).toList();
    }
    if (customerId != null) {
      list = list.where((c) => c.customerId == customerId).toList();
    }
    list.sort((a, b) => b.at.compareTo(a.at));
    if (list.length > limit) list = list.sublist(0, limit);
    return list;
  }

  Future<void> addCallRecord({
    required String phone,
    String? customerId,
    int type = 2,
    int durationSec = 0,
    DateTime? at,
    String? resultStatus,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_callsKey);
    final list = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
    final when = at ?? DateTime.now();
    final norm = Customer.normalizePhone(phone);
    // جلوگیری از ثبت تکراری همان تماس (ظرف ۲ دقیقه)
    for (final e in list.take(15)) {
      final prev = CallRecord.fromJson(Map<String, dynamic>.from(e));
      if (Customer.normalizePhone(prev.phone) == norm &&
          // same phone within window = one event (avoid in+out double)
          true && // was: prev.type == type &&
          (when.difference(prev.at).inSeconds).abs() < 180) {
        return; // skip near-duplicate
      }
    }
    final rec = CallRecord(
      id: const Uuid().v4(),
      phone: norm,
      customerId: customerId,
      type: type,
      at: when,
      durationSec: durationSec,
      resultStatus: resultStatus,
    );
    list.insert(0, rec.toJson());
    // cap storage for battery/storage
    while (list.length > 300) {
      list.removeLast();
    }
    await prefs.setString(_callsKey, jsonEncode(list));
  }


  static const _callChannel = MethodChannel('ir.apadanasleep.customer_callbook/call_log');

  Future<List<Map<String, dynamic>>> fetchRecentDeviceCalls({int days = 1, int limit = 30}) async {
    try {
      final result = await _callChannel.invokeMethod<List>('getRecentCalls', {'days': days});
      if (result == null) return [];
      final list = <Map<String, dynamic>>[];
      for (final e in result) {
        if (e is Map) {
          list.add(Map<String, dynamic>.from(e));
        }
        if (list.length >= limit) break;
      }
      return list;
    } catch (_) {
      return [];
    }
  }


  /// پاکسازی رکوردهای تکراری نزدیک به هم
  Future<int> dedupeCallHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_callsKey);
    if (raw == null || raw.isEmpty) return 0;
    final list = (jsonDecode(raw) as List)
        .map((e) => CallRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    list.sort((a, b) => b.at.compareTo(a.at));
    final kept = <CallRecord>[];
    for (final r in list) {
      final dup = kept.any((k) =>
          Customer.normalizePhone(k.phone) == Customer.normalizePhone(r.phone) &&
          k.type == r.type &&
          (k.at.difference(r.at).inSeconds).abs() < 180);
      if (!dup) kept.add(r);
    }
    final removed = list.length - kept.length;
    if (removed > 0) {
      await prefs.setString(_callsKey, jsonEncode(kept.map((e) => e.toJson()).toList()));
    }
    return removed;
  }




  Future<List<Customer>> getAllRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Customer.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// تعمیر نام و یادداشت‌های خراب‌شده (mojibake)
  Future<void> migrateTextEncoding() async {
    final all = await getAllRaw();
    var changed = false;
    final out = <Customer>[];
    for (final c in all) {
      final n = TextRepair.fix(c.name);
      final note = c.note == null ? null : TextRepair.fix(c.note!);
      final city = c.city == null ? null : TextRepair.fix(c.city!);
      final tag = TextRepair.fix(c.tag);
      final status = TextRepair.fix(c.status);
      if (n != c.name || note != c.note || city != c.city || tag != c.tag || status != c.status) {
        changed = true;
        out.add(c.copyWith(
          name: n.isEmpty ? c.name : n,
          note: note,
          city: city,
          tag: tag.isEmpty ? c.tag : tag,
          status: status.isEmpty ? c.status : status,
        ));
      } else {
        out.add(c);
      }
    }
    if (changed) await _save(out);
  }


  Future<void> updateLatestCallStatus(String phone, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_callsKey);
    if (raw == null || raw.isEmpty) return;
    final list = (jsonDecode(raw) as List)
        .map((e) => CallRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final key = Customer.matchKey(phone);
    for (var i = 0; i < list.length; i++) {
      if (Customer.matchKey(list[i].phone) == key) {
        final r = list[i];
        list[i] = CallRecord(
          id: r.id,
          phone: r.phone,
          customerId: r.customerId,
          type: r.type,
          at: r.at,
          durationSec: r.durationSec,
          resultStatus: status,
        );
        break;
      }
    }
    await prefs.setString(_callsKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<Map<String, int>> todayCallBreakdown() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_callsKey);
    var inC = 0, outC = 0, miss = 0;
    if (raw != null && raw.isNotEmpty) {
      final now = DateTime.now();
      for (final e in (jsonDecode(raw) as List)) {
        final r = CallRecord.fromJson(Map<String, dynamic>.from(e));
        if (r.at.year == now.year && r.at.month == now.month && r.at.day == now.day) {
          if (r.type == 1) inC++;
          else if (r.type == 3) miss++;
          else outC++;
        }
      }
    }
    return {'in': inC, 'out': outC, 'miss': miss, 'total': inC + outC + miss};
  }
}
