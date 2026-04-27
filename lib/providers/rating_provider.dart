import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/services/rating_service.dart';

// ---------------------------------------------------------------------------
// Provider — Rating actual del usuario en un post específico
// ---------------------------------------------------------------------------

typedef RatingParams = ({String collectionName, String postId, String userId});

/// Obtiene el voto actual del usuario para un post dado.
/// Retorna null si aún no ha votado.
/// Se autoDescarta y se invalida manualmente tras cada submit.
final userRatingProvider = FutureProvider.autoDispose
    .family<int?, RatingParams>((ref, params) {
      return RatingService.getUserRating(
        collectionName: params.collectionName,
        postId: params.postId,
        userId: params.userId,
      );
    });
