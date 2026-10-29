class CallRecord {
  final String id;
  final String phone;
  final String? customerId;
  final int type; // 1 in, 2 out, 3 missed
  final DateTime at;
  final int durationSec;
  final String? resultStatus; // وضعیت انتخاب‌شده بعد تماس

  CallRecord({
    required this.id,
    required this.phone,
    this.customerId,
    required this.type,
    required this.at,
    this.durationSec = 0,
    this.resultStatus,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'customerId': customerId,
        'type': type,
        'at': at.toIso8601String(),
        'durationSec': durationSec,
        'resultStatus': resultStatus,
      };

  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
        id: j['id'] as String,
        phone: j['phone'] as String? ?? '',
        customerId: j['customerId'] as String?,
        type: j['type'] as int? ?? 1,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        durationSec: j['durationSec'] as int? ?? 0,
        resultStatus: j['resultStatus'] as String?,
      );

  String get typeLabel {
    switch (type) {
      case 1:
        return 'ورودی';
      case 2:
        return 'خروجی';
      case 3:
        return 'از دست‌رفته';
      default:
        return 'تماس';
    }
  }
}
