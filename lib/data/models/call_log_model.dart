import 'package:uuid/uuid.dart';

class CallLogModel {
  final String id;
  final String customerId;
  final String phone;
  final DateTime dateTime;
  final int durationSeconds;
  final String type; // incoming, outgoing, missed
  String? note;

  CallLogModel({
    String? id,
    required this.customerId,
    required this.phone,
    required this.dateTime,
    this.durationSeconds = 0,
    required this.type,
    this.note,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'phone': phone,
      'dateTime': dateTime.toIso8601String(),
      'durationSeconds': durationSeconds,
      'type': type,
      'note': note,
    };
  }

  factory CallLogModel.fromMap(Map<String, dynamic> map) {
    return CallLogModel(
      id: map['id'],
      customerId: map['customerId'],
      phone: map['phone'],
      dateTime: DateTime.parse(map['dateTime']),
      durationSeconds: map['durationSeconds'] ?? 0,
      type: map['type'],
      note: map['note'],
    );
  }
}
