import 'package:cloud_firestore/cloud_firestore.dart';

enum ContactRequestStatus { pending, accepted, rejected }

class ContactRequest {
  final String id;
  final String fromId;
  final String fromNickname;
  final String? fromFotoUrl;
  final String toId;
  final ContactRequestStatus status;
  final DateTime createdAt;

  ContactRequest({
    required this.id,
    required this.fromId,
    required this.fromNickname,
    this.fromFotoUrl,
    required this.toId,
    required this.status,
    required this.createdAt,
  });

  factory ContactRequest.fromMap(Map<String, dynamic> map, String id) {
    return ContactRequest(
      id: id,
      fromId: map['fromId'] ?? '',
      fromNickname: map['fromNickname'] ?? 'Anónimo',
      fromFotoUrl: map['fromFotoUrl'],
      toId: map['toId'] ?? '',
      status: ContactRequestStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ContactRequestStatus.pending,
      ),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fromId': fromId,
      'fromNickname': fromNickname,
      'fromFotoUrl': fromFotoUrl,
      'toId': toId,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
