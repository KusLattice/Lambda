import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Servicio de rating para Hospedaje (lodging_tracker) y Picás (food_tracker).
/// Cada usuario puede votar una vez; si vota de nuevo, reemplaza el voto anterior.
/// El promedio y el conteo se mantienen en el documento padre mediante transacción atómica.
class RatingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Envía o actualiza el voto de [userId] para [postId] en [collectionName].
  /// [value] debe estar entre 1 y 5.
  static Future<void> submitRating({
    required String collectionName,
    required String postId,
    required String userId,
    required int value,
  }) async {
    assert(value >= 1 && value <= 5, 'El rating debe ser entre 1 y 5');

    final postRef = _db.collection(collectionName).doc(postId);
    final ratingRef = postRef.collection('ratings').doc(userId);

    await _db.runTransaction((transaction) async {
      final postSnap = await transaction.get(postRef);
      final ratingSnap = await transaction.get(ratingRef);

      final currentCount = (postSnap.data()?['ratingCount'] as int?) ?? 0;
      final currentSum =
          (postSnap.data()?['ratingSum'] as num?)?.toDouble() ?? 0.0;

      double newSum;
      int newCount;

      if (ratingSnap.exists) {
        // Reemplazar el voto anterior
        final oldValue = (ratingSnap.data()?['value'] as int?) ?? 0;
        newSum = currentSum - oldValue + value;
        newCount = currentCount; // el conteo no cambia
      } else {
        // Nuevo voto
        newSum = currentSum + value;
        newCount = currentCount + 1;
      }

      final newAverage = newCount > 0 ? newSum / newCount : 0.0;

      transaction.set(ratingRef, {
        'value': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(postRef, {
        'ratingSum': newSum,
        'ratingCount': newCount,
        'ratingAverage': double.parse(newAverage.toStringAsFixed(1)),
      });
    });
  }

  /// Obtiene el voto actual del usuario para un post, o null si no ha votado.
  static Future<int?> getUserRating({
    required String collectionName,
    required String postId,
    required String userId,
  }) async {
    try {
      final doc = await _db
          .collection(collectionName)
          .doc(postId)
          .collection('ratings')
          .doc(userId)
          .get();
      if (!doc.exists) return null;
      return (doc.data()?['value'] as int?);
    } catch (e) {
      debugPrint(
        'RatingService: Error obteniendo rating de $userId para $postId: $e',
      );
      return null;
    }
  }
}
