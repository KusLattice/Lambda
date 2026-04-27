import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Modelo de comentario adjunto a cualquier post de la app.
/// Se almacena en subcollecciones: `{collection}/{postId}/comments/{commentId}`
@immutable
class PostComment {
  final String id;
  final String postId;
  final String authorId;
  final String authorNickname;
  final String? authorFotoUrl;
  final String body;
  final DateTime createdAt;

  /// Reacciones: Map<emojiKey, List<userId>>
  /// Ejemplo: { "fire": ["uid1", "uid2"], "like": ["uid3"] }
  final Map<String, List<String>> reactions;

  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorNickname,
    this.authorFotoUrl,
    required this.body,
    required this.createdAt,
    this.reactions = const {},
  });

  PostComment copyWith({
    String? id,
    String? postId,
    String? authorId,
    String? authorNickname,
    String? authorFotoUrl,
    String? body,
    DateTime? createdAt,
    Map<String, List<String>>? reactions,
  }) {
    return PostComment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      authorId: authorId ?? this.authorId,
      authorNickname: authorNickname ?? this.authorNickname,
      authorFotoUrl: authorFotoUrl ?? this.authorFotoUrl,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      reactions: reactions ?? this.reactions,
    );
  }

  factory PostComment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parsear reactions: Map<String, List<dynamic>> → Map<String, List<String>>
    final rawReactions = data['reactions'] as Map<String, dynamic>?;
    final parsedReactions = <String, List<String>>{};
    if (rawReactions != null) {
      rawReactions.forEach((key, value) {
        if (value is List) {
          parsedReactions[key] = value.map((e) => e.toString()).toList();
        }
      });
    }

    return PostComment(
      id: doc.id,
      postId: data['postId'] ?? '',
      authorId: data['authorId'] ?? '',
      authorNickname: data['authorNickname'] ?? 'Anónimo',
      authorFotoUrl: data['authorFotoUrl'] as String?,
      body: data['body'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reactions: parsedReactions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'authorId': authorId,
      'authorNickname': authorNickname,
      'authorFotoUrl': authorFotoUrl,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
      'reactions': {},
    };
  }

  // Helpers de conveniencia
  int reactionCount(String key) => reactions[key]?.length ?? 0;
  bool hasReacted(String key, String userId) =>
      reactions[key]?.contains(userId) ?? false;
  int get totalReactions =>
      reactions.values.fold(0, (acc, list) => acc + list.length);
}
