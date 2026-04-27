import 'package:cloud_firestore/cloud_firestore.dart';

enum AdminRequestType { duda, sugerencia, reclamo, ascenso }

extension AdminRequestTypeExtension on AdminRequestType {
  String get displayName {
    switch (this) {
      case AdminRequestType.duda:
        return 'Duda';
      case AdminRequestType.sugerencia:
        return 'Sugerencia';
      case AdminRequestType.reclamo:
        return 'Reclamo';
      case AdminRequestType.ascenso:
        return 'Solicitud de Ascenso';
    }
  }

  String get id {
    return name;
  }
}

class AdminRequest {
  final String id;
  final String senderId;
  final String senderName;
  final AdminRequestType type;
  final String subject;
  final String body;
  final DateTime createdAt;
  final String? attendedBy;
  final String? attendedByName;
  final bool isResolved;

  AdminRequest({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.type,
    required this.subject,
    required this.body,
    required this.createdAt,
    this.attendedBy,
    this.attendedByName,
    this.isResolved = false,
  });

  factory AdminRequest.fromMap(Map<String, dynamic> map, String id) {
    return AdminRequest(
      id: id,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Anónimo',
      type: AdminRequestType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AdminRequestType.duda,
      ),
      subject: map['subject'] ?? '',
      body: map['body'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      attendedBy: map['attendedBy'],
      attendedByName: map['attendedByName'],
      isResolved: map['isResolved'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'type': type.name,
      'subject': subject,
      'body': body,
      'createdAt': Timestamp.fromDate(createdAt),
      'attendedBy': attendedBy,
      'attendedByName': attendedByName,
      'isResolved': isResolved,
    };
  }

  AdminRequest copyWith({
    String? attendedBy,
    String? attendedByName,
    bool? isResolved,
  }) {
    return AdminRequest(
      id: id,
      senderId: senderId,
      senderName: senderName,
      type: type,
      subject: subject,
      body: body,
      createdAt: createdAt,
      attendedBy: attendedBy ?? this.attendedBy,
      attendedByName: attendedByName ?? this.attendedByName,
      isResolved: isResolved ?? this.isResolved,
    );
  }
}
