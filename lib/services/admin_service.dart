import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/admin_request_model.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/models/message_model.dart';
import 'package:lambda_app/services/notification_service.dart';
import 'package:uuid/uuid.dart';

final adminServiceProvider = Provider((ref) => AdminService());

class AdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  /// Envía una nueva solicitud de un usuario a los admins.
  Future<void> submitRequest({
    required String senderId,
    required String senderName,
    required AdminRequestType type,
    required String subject,
    required String body,
  }) async {
    final requestId = _uuid.v4();

    final request = AdminRequest(
      id: requestId,
      senderId: senderId,
      senderName: senderName,
      type: type,
      subject: subject,
      body: body,
      createdAt: DateTime.now(),
    );

    await _db.collection('admin_requests').doc(requestId).set(request.toMap());
  }

  /// Stream de solicitudes para el Panel de Admin.
  Stream<List<AdminRequest>> getRequestsStream() {
    return _db
        .collection('admin_requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => AdminRequest.fromMap(doc.data(), doc.id))
              .toList();
        });
  }

  /// Un admin marca que está atendiendo el tema para evitar duplicados.
  Future<void> markAsAttending(
    String requestId,
    String adminId,
    String adminName,
  ) async {
    await _db.collection('admin_requests').doc(requestId).update({
      'attendedBy': adminId,
      'attendedByName': adminName,
    });
  }

  /// Libera el tema si el admin lo cierra sin resolver.
  Future<void> releaseRequest(String requestId) async {
    await _db.collection('admin_requests').doc(requestId).update({
      'attendedBy': null,
      'attendedByName': null,
    });
  }

  /// Resuelve la solicitud y envía una respuesta formal al usuario.
  Future<void> resolveRequest({
    required AdminRequest request,
    required String responseBody,
    required String adminId,
    required String adminName,
  }) async {
    final batch = _db.batch();

    // 1. Marcar solicitud como resuelta
    final requestRef = _db.collection('admin_requests').doc(request.id);
    batch.update(requestRef, {'isResolved': true});

    // 2. Crear mensaje formal para el usuario (Correo λ)
    final messageId = _uuid.v4();
    final message = Message(
      id: messageId,
      senderId: 'system_admin',
      receiverId: request.senderId,
      subject: 'RE: ${request.type.displayName} - ${request.subject}',
      body:
          'Hola ${request.senderName},\n\nRespuesta de administración:\n$responseBody\n\nSaludos,\nEquipo Lambda.',
      timestamp: DateTime.now(),
      isRead: false,
      chatId: Message.buildChatId('system_admin', request.senderId),
      labels: const ['inbox'],
      ownerId: request.senderId,
    );

    final msgRef = _db.collection('messages').doc(messageId);
    batch.set(msgRef, message.toMap());

    await batch.commit();

    // 3. Notificar con campanita 🔔
    await NotificationService.notifyNewMail(
      targetUserId: request.senderId,
      sourceUserId: 'system_admin',
      sourceUserName: 'ADMINISTRACIÓN λ',
      subject: message.subject,
    );
  }

  /// Procesa una solicitud de ascenso (Aprobar o Denegar).
  Future<void> handlePromotionRequest({
    required AdminRequest request,
    required bool approve,
    required String adminId,
    required String adminName,
    String? reason,
  }) async {
    final batch = _db.batch();

    // 1. Marcar solicitud como resuelta
    final requestRef = _db.collection('admin_requests').doc(request.id);
    batch.update(requestRef, {
      'isResolved': true,
      'attendedBy': adminId,
      'attendedByName': adminName,
    });

    // 2. Si aprueba, subir rango al usuario
    if (approve) {
      final userRef = _db.collection('users').doc(request.senderId);
      batch.update(userRef, {'role': UserRole.TecnicoVerificado.name});
    }

    // 3. Crear mensaje formal (Correo λ)
    final messageId = _uuid.v4();
    final subject = approve
        ? 'SOLICITUD DE ASCENSO APROBADA'
        : 'SOLICITUD DE ASCENSO DENEGADA';
    final resultText = approve
        ? '¡Felicidades! Tu solicitud de ascenso ha sido aprobada. Ahora eres un Usuario Verificado en la red λ.'
        : 'Lo sentimos, tu solicitud de ascenso ha sido denegada en este momento.';

    final body =
        '$resultText\n\n${reason != null ? "Motivo: $reason\n\n" : ""}Saludos,\nEquipo Lambda.';

    final message = Message(
      id: messageId,
      senderId: 'system_admin',
      receiverId: request.senderId,
      subject: subject,
      body: body,
      timestamp: DateTime.now(),
      isRead: false,
      chatId: Message.buildChatId('system_admin', request.senderId),
      labels: const ['inbox'],
      ownerId: request.senderId,
    );

    final msgRef = _db.collection('messages').doc(messageId);
    batch.set(msgRef, message.toMap());

    await batch.commit();

    // 4. Notificar con campanita 🔔
    await NotificationService.notifyNewMail(
      targetUserId: request.senderId,
      sourceUserId: 'system_admin',
      sourceUserName: 'ADMINISTRACIÓN λ',
      subject: message.subject,
    );
  }

  /// Realiza una búsqueda profunda en todos los mensajes del sistema.
  /// Retorna mensajes que contienen el texto buscado en el cuerpo (body).
  Future<List<Message>> deepSearchMessages(String query) async {
    if (query.trim().isEmpty) return [];
    
    final queryLower = query.toLowerCase();
    
    // NOTA: Firestore no tiene búsqueda Full-Text. 
    // Filtramos en memoria sobre los últimos 1000 mensajes para auditoría rápida.
    final snapshot = await _db
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1000)
        .get();

    return snapshot.docs
        .map((doc) => Message.fromMap(doc.data(), doc.id))
        .where((m) => m.body.toLowerCase().contains(queryLower))
        .toList();
  }
}
