import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lambda_app/models/notification_model.dart';

/// Servicio centralizado para crear notificaciones.
/// Asegura consistencia en la estructura de datos y evita duplicación.
class NotificationService {
  static final _collection = FirebaseFirestore.instance.collection(
    'notifications',
  );

  /// Notifica al destinatario de un nuevo mensaje de correo.
  static Future<void> notifyNewMail({
    required String targetUserId,
    required String sourceUserId,
    required String sourceUserName,
    required String subject,
  }) async {
    // No notificar si el usuario se envía a sí mismo
    if (targetUserId == sourceUserId) return;

    final notification = AppNotification(
      id: '',
      targetUserId: targetUserId,
      sourceUserId: sourceUserId,
      sourceUserName: sourceUserName,
      type: NotificationType.mail,
      title: 'te envió un mensaje',
      body: subject,
      routeName: '/mail',
      createdAt: DateTime.now(),
    );
    await _collection.add(notification.toMap());
  }

  /// Notifica al dueño de un post sobre un comentario.
  static Future<void> notifyComment({
    required String targetUserId,
    required String sourceUserId,
    required String sourceUserName,
    required String postTitle,
    required String routeName,
    required String postId,
  }) async {
    if (targetUserId == sourceUserId) return;

    final notification = AppNotification(
      id: '',
      targetUserId: targetUserId,
      sourceUserId: sourceUserId,
      sourceUserName: sourceUserName,
      type: NotificationType.comment,
      title: 'comentó tu publicación',
      body: postTitle,
      routeName: routeName,
      routeArg: postId,
      createdAt: DateTime.now(),
    );
    await _collection.add(notification.toMap());
  }

  /// Notifica al dueño de un post sobre una reacción.
  static Future<void> notifyReaction({
    required String targetUserId,
    required String sourceUserId,
    required String sourceUserName,
    required String postTitle,
    required String routeName,
    required String postId,
  }) async {
    if (targetUserId == sourceUserId) return;

    final notification = AppNotification(
      id: '',
      targetUserId: targetUserId,
      sourceUserId: sourceUserId,
      sourceUserName: sourceUserName,
      type: NotificationType.reaction,
      title: 'reaccionó a tu publicación',
      body: postTitle,
      routeName: routeName,
      routeArg: postId,
      createdAt: DateTime.now(),
    );
    await _collection.add(notification.toMap());
  }

  /// Notifica al dueño de una chamba que alguien está interesado.
  static Future<void> notifyChamba({
    required String targetUserId,
    required String sourceUserId,
    required String sourceUserName,
    required String chambaTitle,
    required String chambaId,
  }) async {
    if (targetUserId == sourceUserId) return;
    final notification = AppNotification(
      id: '',
      targetUserId: targetUserId,
      sourceUserId: sourceUserId,
      sourceUserName: sourceUserName,
      type: NotificationType.comment, // Reutilizando tipo comentario
      title: 'está interesado en tu chamba',
      body: chambaTitle,
      routeName: '/chambas',
      routeArg: chambaId,
      createdAt: DateTime.now(),
    );
    await _collection.add(notification.toMap());
  }
}
