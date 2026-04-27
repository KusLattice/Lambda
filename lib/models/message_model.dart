import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String subject;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final List<String> labels; // inbox, sent, trash — retrocompatibilidad
  /// ID de conversación determinista: sorted([senderId, receiverId]).join('_')
  final String chatId;

  /// ID del usuario propietario de esta copia (necesario para aislar Mail tradicional)
  final String? ownerId;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.subject,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.imageUrls = const [],
    this.videoUrls = const [],
    this.labels = const [],
    this.chatId = '',
    this.ownerId,
  });

  /// Genera el chatId canónico para un par de usuarios.
  /// Siempre produce el mismo resultado independientemente del orden de los UIDs.
  static String buildChatId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? subject,
    String? body,
    DateTime? timestamp,
    bool? isRead,
    List<String>? imageUrls,
    List<String>? videoUrls,
    List<String>? labels,
    String? chatId,
    String? ownerId,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      labels: labels ?? this.labels,
      chatId: chatId ?? this.chatId,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  factory Message.fromMap(Map<String, dynamic> map, String id) {
    final senderId = (map['senderId'] as String?) ?? '';
    final receiverId = (map['receiverId'] as String?) ?? '';
    return Message(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      subject: (map['subject'] as String?) ?? '',
      body: (map['body'] as String?) ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: (map['isRead'] as bool?) ?? false,
      imageUrls: List<String>.from(map['imageUrls'] as List? ?? []),
      videoUrls: List<String>.from(map['videoUrls'] as List? ?? []),
      labels: List<String>.from(map['labels'] as List? ?? []),
      // Para mensajes de chat que no tengan chatId, lo reconstruimos.
      // Los correos tienen ownerId y/o subject, y NO deben llevar un chatId asimilado para evitar agrupación indebida.
      chatId: ((map['chatId'] as String?) ?? '').isNotEmpty
          ? map['chatId'] as String
          : ((map['ownerId'] == null && map['subject'] == '') ||
                  senderId == 'system_admin' ||
                  receiverId == 'system_admin'
                ? Message.buildChatId(senderId, receiverId)
                : ''),
      ownerId: map['ownerId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'subject': subject,
      'body': body,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': isRead,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'labels': labels,
      'chatId': chatId,
      'ownerId': ownerId,
    };
  }
}

@immutable
class Contact {
  final String userId;
  final String lastMessage;
  final DateTime lastInteraction;

  const Contact({
    required this.userId,
    required this.lastMessage,
    required this.lastInteraction,
  });

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      userId: (map['userId'] as String?) ?? '',
      lastMessage: (map['lastMessage'] as String?) ?? '',
      lastInteraction: (map['lastInteraction'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'lastMessage': lastMessage,
      'lastInteraction': Timestamp.fromDate(lastInteraction),
    };
  }
}
