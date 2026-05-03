import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos de notificación soportados.
enum NotificationType { comment, reaction, mention, newPost, mail, chamba, system }

/// Modelo de notificación para el sistema de alertas Lambda.
/// Se almacena en la colección `notifications` de Firestore.
class AppNotification {
  final String id;
  final String targetUserId; // A quién va dirigida
  final String sourceUserId; // Quién generó la acción
  final String sourceUserName; // Nombre visible del actor
  final NotificationType type;
  final String title; // Título resumido, ej: "Comentó tu publicación"
  final String body; // Detalle, ej: nombre del post
  final String? routeName; // Ruta de navegación, ej: '/food'
  final String? routeArg; // Argumento de ruta, ej: postId
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.targetUserId,
    required this.sourceUserId,
    required this.sourceUserName,
    required this.type,
    required this.title,
    required this.body,
    this.routeName,
    this.routeArg,
    required this.createdAt,
    this.isRead = false,
  });

  AppNotification copyWith({
    String? id,
    String? targetUserId,
    String? sourceUserId,
    String? sourceUserName,
    NotificationType? type,
    String? title,
    String? body,
    String? routeName,
    String? routeArg,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      targetUserId: targetUserId ?? this.targetUserId,
      sourceUserId: sourceUserId ?? this.sourceUserId,
      sourceUserName: sourceUserName ?? this.sourceUserName,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      routeName: routeName ?? this.routeName,
      routeArg: routeArg ?? this.routeArg,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppNotification(
      id: doc.id,
      targetUserId: data['targetUserId'] ?? '',
      sourceUserId: data['sourceUserId'] ?? '',
      sourceUserName: data['sourceUserName'] ?? 'Alguien',
      type: NotificationType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => NotificationType.newPost,
      ),
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      routeName: data['routeName'] as String?,
      routeArg: data['routeArg'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'targetUserId': targetUserId,
      'sourceUserId': sourceUserId,
      'sourceUserName': sourceUserName,
      'type': type.name,
      'title': title,
      'body': body,
      if (routeName != null) 'routeName': routeName,
      if (routeArg != null) 'routeArg': routeArg,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': isRead,
    };
  }

  /// Icono representativo del tipo de notificación.
  String get emoji {
    switch (type) {
      case NotificationType.comment:
        return '💬';
      case NotificationType.reaction:
        return '⚡';
      case NotificationType.mention:
        return '📢';
      case NotificationType.newPost:
        return '📌';
      case NotificationType.mail:
        return '📬';
      case NotificationType.chamba:
        return '🛠️';
      case NotificationType.system:
        return '🛡️';
    }
  }
}
