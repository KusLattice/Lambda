import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/comment_model.dart';

// ---------------------------------------------------------------------------
// Provider — Stream de comentarios para un post específico
// Param: record ({ postId, collectionName })
// ---------------------------------------------------------------------------

typedef CommentParams = ({String postId, String collectionName});

/// Stream reactivo de comentarios. Se auto-descarta cuando no hay widgets observándolo.
final commentsProvider = StreamProvider.autoDispose
    .family<List<PostComment>, CommentParams>((ref, params) {
      return FirebaseFirestore.instance
          .collection(params.collectionName)
          .doc(params.postId)
          .collection('comments')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => PostComment.fromFirestore(doc))
                .toList(),
          );
    });

// ---------------------------------------------------------------------------
// Servicio de comentarios — CRUD + Reacciones
// ---------------------------------------------------------------------------

/// Catálogo de reacciones disponibles en la app Lambda.
const List<Map<String, String>> kLambdaReactions = [
  {'key': 'like', 'emoji': '👍', 'label': 'Like'},
  {'key': 'fire', 'emoji': '🔥', 'label': 'Técnico'},
  {'key': 'bolt', 'emoji': '⚡', 'label': 'Urgente'},
  {'key': 'target', 'emoji': '🎯', 'label': 'Preciso'},
  {'key': 'lol', 'emoji': '😂', 'label': 'Jajaja'},
];

class CommentService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Referencia a la subcollección de comentarios de un post.
  static CollectionReference<Map<String, dynamic>> _commentsRef({
    required String collectionName,
    required String postId,
  }) =>
      _db.collection(collectionName).doc(postId).collection('comments');

  /// Agrega un nuevo comentario en la subcollección del post.
  static Future<void> addComment({
    required String collectionName,
    required String postId,
    required PostComment comment,
  }) async {
    await _commentsRef(collectionName: collectionName, postId: postId)
        .add(comment.toMap());
  }

  /// Elimina un comentario. Solo se puede si el usuario es el autor o admin.
  /// La validación de permisos se hace en el widget antes de llamar esto;
  /// las reglas de Firestore son la barrera final.
  static Future<void> deleteComment({
    required String collectionName,
    required String postId,
    required String commentId,
  }) async {
    try {
      await _commentsRef(collectionName: collectionName, postId: postId)
          .doc(commentId)
          .delete();
    } catch (e) {
      debugPrint('CommentService: Error borrando comentario $commentId: $e');
      rethrow;
    }
  }

  /// Toggle de reacción: añade si no existe, quita si ya reaccionó.
  /// Usa transacción para evitar race conditions.
  static Future<void> toggleReaction({
    required String collectionName,
    required String postId,
    required String commentId,
    required String reactionKey,
    required String userId,
  }) async {
    final docRef = _commentsRef(
      collectionName: collectionName,
      postId: postId,
    ).doc(commentId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;

        final data = snap.data()!;
        final reactions = Map<String, dynamic>.from(
          (data['reactions'] as Map<String, dynamic>?) ?? {},
        );

        final currentList = List<String>.from(
          (reactions[reactionKey] as List<dynamic>?) ?? [],
        );

        if (currentList.contains(userId)) {
          currentList.remove(userId);
        } else {
          currentList.add(userId);
        }

        reactions[reactionKey] = currentList;
        tx.update(docRef, {'reactions': reactions});
      });
    } catch (e) {
      debugPrint('CommentService: Error en toggleReaction: $e');
      rethrow;
    }
  }
}
