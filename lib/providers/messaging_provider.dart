import 'dart:io';
import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/models/message_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/services/notification_service.dart';
import 'package:lambda_app/config/firestore_collections.dart';
import 'package:lambda_app/services/storage_upload_service.dart';

final messagingProvider = Provider((ref) => MessagingService(ref));

class MessagingService {
  final Ref _ref;
  MessagingService(this._ref);

  FirebaseFirestore get _firestore => _ref.read(firestoreProvider);
  User? get _currentUser => _ref.read(authProvider).valueOrNull;

  /// Mueve un mensaje de chat a la papelera PRIVADA del usuario.
  Future<void> deleteChatMessage(String messageId) async {
    final user = _currentUser;
    if (user == null) return;

    await _firestore.collection(FC.messages).doc(messageId).update({
      'labels': FieldValue.arrayUnion(['trash_${user.id}']),
    });
  }

  Future<void> deleteChatConversation(String chatId) async {
    final user = _currentUser;
    if (user == null) return;

    final snap = await _firestore
        .collection(FC.messages)
        .where('chatId', isEqualTo: chatId)
        .get();

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'labels': FieldValue.arrayUnion(['trash_${user.id}']),
      });
    }

    if (snap.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  /// Elimina definitivamente un mensaje.
  /// Para correos tradicionales, borra el documento.
  /// Para chats, solo lo oculta visualmente; lo borra de la BD solo si la otra persona también lo borró.
  Future<void> permanentlyDeleteMessage(String messageId) async {
    final user = _currentUser;
    if (user == null) return;

    final doc = await _firestore.collection(FC.messages).doc(messageId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    // Si es un correo tradicional (ownerId presente) lo borramos de inmediato.
    if (data['ownerId'] != null) {
      await doc.reference.delete();
      return;
    }

    final labels = List<String>.from(data['labels'] ?? []);
    final otherUserId = data['senderId'] == user.id
        ? data['receiverId']
        : data['senderId'];
    final isDeletedByOther = labels.contains('deleted_$otherUserId');

    if (isDeletedByOther) {
      await doc.reference.delete();
    } else {
      labels.remove('trash');
      labels.remove('trash_${user.id}');
      if (!labels.contains('deleted_${user.id}')) {
        labels.add('deleted_${user.id}');
      }
      await doc.reference.update({'labels': labels});
    }
  }

  /// Restaura una conversación completa de la papelera (Chat).
  Future<void> restoreChatConversation(String chatId) async {
    final user = _currentUser;
    if (user == null) return;

    final snap = await _firestore
        .collection(FC.messages)
        .where('chatId', isEqualTo: chatId)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      final labels = List<String>.from(doc.data()['labels'] ?? []);
      if (labels.contains('trash_${user.id}')) {
        batch.update(doc.reference, {
          'labels': FieldValue.arrayRemove(['trash', 'trash_${user.id}']),
        });
      }
    }
    await batch.commit();
  }

  /// Elimina definitivamente todos los mensajes de un chat que estaban en papelera para este usuario.
  Future<void> permanentlyDeleteChatConversation(String chatId) async {
    final user = _currentUser;
    if (user == null) return;

    final snap = await _firestore
        .collection(FC.messages)
        .where('chatId', isEqualTo: chatId)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      final data = doc.data();

      final labels = List<String>.from(data['labels'] ?? []);
      final otherUserId = data['senderId'] == user.id
          ? data['receiverId']
          : data['senderId'];
      final isDeletedByOther = labels.contains('deleted_$otherUserId');

      if (labels.contains('trash_${user.id}')) {
        if (isDeletedByOther) {
          batch.delete(doc.reference);
        } else {
          labels.remove('trash');
          labels.remove('trash_${user.id}');
          if (!labels.contains('deleted_${user.id}')) {
            labels.add('deleted_${user.id}');
          }
          batch.update(doc.reference, {'labels': labels});
        }
      }
    }
    await batch.commit();
  }

  Future<void> sendChatMessage({
    required String receiverId,
    required String body,
    List<File> images = const [],
    List<File> videoFiles = const [],
    String? senderIdOverride,
  }) async {
    final user = _currentUser;
    if (user == null) throw Exception('No autenticado.');
    if (body.trim().isEmpty && images.isEmpty && videoFiles.isEmpty) return;

    final effectiveSenderId = senderIdOverride ?? user.id;

    final isAdmin = user.isAdmin;
    if (!isAdmin &&
        !user.contactIds.contains(receiverId) &&
        senderIdOverride != 'system_admin') {
      throw Exception(
        'Solo puedes chatear con colegas de tu Red Galáctica. ¡Añádelo primero!',
      );
    }

    final List<String> imageUrls = await StorageUploadService.uploadImages(images, 'messages');

    final List<String> videoUrls = [];
    for (final video in videoFiles) {
      final url = await StorageUploadService.uploadVideo(video, 'messages');
      if (url != null) videoUrls.add(url);
    }

    final chatId = Message.buildChatId(effectiveSenderId, receiverId);
    final message = Message(
      id: '',
      senderId: effectiveSenderId,
      receiverId: receiverId,
      subject: '',
      body: body.trim(),
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      timestamp: DateTime.now(),
      labels: const [],
      chatId: chatId,
    );

    await _firestore.collection(FC.messages).add(message.toMap());

    final senderName = (user.apodo?.isNotEmpty == true)
        ? user.apodo!
        : user.nombre;
    NotificationService.notifyNewMail(
      targetUserId: receiverId,
      sourceUserId: user.id,
      sourceUserName: senderName,
      subject: body.trim().length > 50
          ? '${body.trim().substring(0, 50)}…'
          : body.trim(),
    );

    if (!user.contactIds.contains(receiverId)) {
      await _firestore.collection(FC.users).doc(user.id).update({
        'contactIds': FieldValue.arrayUnion([receiverId]),
      });
      // Note: We can't update authProvider state directly from here easily if it's a notifier.
      // But authProvider is an AsyncNotifier, it should probably be updated by its own notifier.
      // However, for now we follow the instruction of extracting the methods.
      _ref.read(authProvider.notifier).addContact(receiverId);
    }
  }

  /// Obtiene un stream de mensajes para una etiqueta específica (inbox, sent, trash).
  Stream<List<Message>> getMessagesStream(String label) {
    final user = _currentUser;
    if (user == null) return Stream.value([]);

    Query query = _firestore.collection(FC.messages);

    final String labelToQuery = label == 'trash' ? 'trash_${user.id}' : label;

    if (label == 'sent') {
      query = query.where('senderId', isEqualTo: user.id);
    } else if (label != 'trash') {
      query = query.where('receiverId', isEqualTo: user.id);
    }

    return query
        .where('labels', arrayContains: labelToQuery)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) =>
                    Message.fromMap(doc.data() as Map<String, dynamic>, doc.id),
              )
              .where((msg) {
                if (msg.ownerId != null && msg.ownerId != user.id) return false;
                if (label != 'trash') {
                  if (msg.labels.contains('trash')) return false;
                  if (msg.labels.contains('trash_${user.id}')) return false;
                }
                return true;
              })
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        });
  }

  /// Restaura un mensaje de la papelera.
  Future<void> restoreMessageFromTrash(String messageId) async {
    final user = _currentUser;
    if (user == null) return;

    await _firestore.collection(FC.messages).doc(messageId).update({
      'labels': FieldValue.arrayRemove(['trash', 'trash_${user.id}']),
    });
  }

  /// Mueve un mensaje a la papelera.
  Future<void> moveMessageToTrash(String messageId) async {
    final user = _currentUser;
    if (user == null) return;

    // Usamos tanto la global para Mail como la privada para Chat para seguridad
    await _firestore.collection(FC.messages).doc(messageId).update({
      'labels': FieldValue.arrayUnion(['trash', 'trash_${user.id}']),
    });
  }

  Future<void> markChatMessagesAsRead(String chatId) async {
    final user = _currentUser;
    if (user == null) return;

    final isAdmin = user.isAdmin;

    try {
      final receiverIds = [user.id];
      if (isAdmin) receiverIds.add('system_admin');

      final snap = await _firestore
          .collection(FC.messages)
          .where('receiverId', whereIn: receiverIds)
          .where('isRead', isEqualTo: false)
          .get();

      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      int updatedCount = 0;
      for (final doc in snap.docs) {
        final msgData = doc.data();
        final msgChatId = msgData['chatId'] as String? ?? '';

        bool matches = false;
        if (msgChatId == chatId) {
          matches = true;
        } else if (msgChatId.isEmpty) {
          final senderId = msgData['senderId'] as String? ?? '';
          final receiverId = msgData['receiverId'] as String? ?? '';
          if (Message.buildChatId(senderId, receiverId) == chatId) {
            matches = true;
          }
        }

        if (matches) {
          batch.update(doc.reference, {'isRead': true});
          updatedCount++;
        }
      }

      if (updatedCount > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('markChatMessagesAsRead error: $e');
    }
  }

  Stream<List<Message>> getChatMessagesStream(String chatId) {
    final user = _currentUser;
    if (user == null) return Stream.value([]);

    final isAdmin = user.isAdmin;

    return _firestore
        .collection(FC.messages)
        .where('chatId', isEqualTo: chatId)
        .orderBy('timestamp')
        .snapshots()
        .handleError((e) {
          debugPrint('getChatMessagesStream error: $e');
        })
        .map((snap) {
          final messages = snap.docs
              .map((doc) {
                return Message.fromMap(doc.data(), doc.id);
              })
              .where((msg) {
                final bool isSystemInvolved =
                    msg.senderId == 'system_admin' ||
                    msg.receiverId == 'system_admin';
                final bool canSeeSharedAdmin = isAdmin && isSystemInvolved;

                if (msg.ownerId != null &&
                    msg.ownerId != user.id &&
                    !canSeeSharedAdmin) {
                  return false;
                }

                if (msg.labels.contains('trash')) return false;
                if (msg.labels.contains('trash_${user.id}')) return false;
                if (msg.labels.contains('deleted_${user.id}')) return false;

                return true;
              })
              .toList();

          return messages;
        });
  }

  Stream<List<User>> getContactsStream() {
    final user = _currentUser;
    if (user == null || user.contactIds.isEmpty) return Stream.value([]);

    // Firestore whereIn máximo: 30 elementos
    final ids = user.contactIds.take(30).toList();

    return _firestore
        .collection(FC.users)
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => User.fromMap(doc.data(), doc.id)).toList());
  }

  Stream<List<Message>> getChatConversationsStream() {
    final user = _currentUser;
    if (user == null) return Stream.value([]);

    final isAdmin = user.isAdmin;

    // UNA sola lista — reutilizada tanto en StreamGroup como en asyncExpand.
    final streams = <Stream<QuerySnapshot>>[
      _firestore
          .collection(FC.messages)
          .where('senderId', isEqualTo: user.id)
          .snapshots(),
      _firestore
          .collection(FC.messages)
          .where('receiverId', isEqualTo: user.id)
          .snapshots(),
      if (isAdmin) ...[
        _firestore
            .collection(FC.messages)
            .where('senderId', isEqualTo: 'system_admin')
            .snapshots(),
        _firestore
            .collection(FC.messages)
            .where('receiverId', isEqualTo: 'system_admin')
            .snapshots(),
      ],
    ];

    return StreamGroup.merge(streams)
        .map((_) => <List<Message>>[])
        .asyncExpand((_) async* {
          // Lecturas en paralelo — más rápido que el for-loop secuencial.
          final snaps = await Future.wait(streams.map((s) => s.first));

          final allMessages = snaps
              .expand((s) => s.docs)
              .map((doc) =>
                  Message.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .toList();

          final Map<String, Message> latestByChatId = {};
          for (final msg in allMessages) {
            if (msg.chatId.isEmpty) continue;

            final bool isSystemInvolved =
                msg.senderId == 'system_admin' ||
                msg.receiverId == 'system_admin';
            final bool canSeeSharedAdmin = isAdmin && isSystemInvolved;

            if (msg.ownerId != null &&
                msg.ownerId != user.id &&
                !canSeeSharedAdmin) {
              continue;
            }

            if (msg.labels.contains('trash_${user.id}')) continue;
            if (msg.labels.contains('deleted_${user.id}')) continue;
            if (msg.labels.contains('trash')) continue;

            final existing = latestByChatId[msg.chatId];
            if (existing == null || msg.timestamp.isAfter(existing.timestamp)) {
              latestByChatId[msg.chatId] = msg;
            }
          }

          yield latestByChatId.values.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        })
        .distinct((prev, next) {
          if (prev.length != next.length) return false;
          for (int i = 0; i < prev.length; i++) {
            if (prev[i].id != next[i].id ||
                prev[i].timestamp != next[i].timestamp) return false;
          }
          return true;
        });
  }

  Future<void> addContact(String contactId) async {
    final user = _currentUser;
    if (user == null) return;
    if (!user.contactIds.contains(contactId)) {
      await _ref.read(authProvider.notifier).addContact(contactId);
    }
  }
}
