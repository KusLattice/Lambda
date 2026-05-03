import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/services/search_service.dart';
import 'package:lambda_app/models/lat_lng.dart' as local_coords;

/// Define la estructura del resultado de búsqueda semántica.
class SemanticResult {
  final String id;
  final String content;
  final String title;
  final String source; // 'hospedaje', 'picás', 'mercado', 'secret_vault', etc.
  final double score;
  final double? distance; // Distance in km from user
  final local_coords.LatLng? coordinates; // To show on map if relevant

  SemanticResult({
    required this.id,
    required this.content,
    required this.title,
    required this.source,
    required this.score,
    this.distance,
    this.coordinates,
  });
}

class SemanticSearchNotifier
    extends StateNotifier<AsyncValue<List<SemanticResult>>> {
  final Ref ref;
  final SearchService _searchService = SearchService();

  SemanticSearchNotifier(this.ref) : super(const AsyncValue.data([]));

  /// Realiza la búsqueda semántica con protocolo de seguridad.
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    state = const AsyncValue.loading();
    try {
      // Búsqueda inteligente omnidireccional con privilegios de admin si corresponde
      final allResults = await _searchService.performOmniSearch(
        query,
        isAdmin: user.isAdmin,
        userLocation: user.lastKnownPosition,
      );

      // Protocolo de Seguridad Táctico: Filtrado por Rol y Permisos
      final filteredResults = allResults.where((res) {
        // SuperAdmins y Admins tienen acceso total maestro
        if (user.isAdmin) {
          return true;
        }

        // Filtrado por características bloqueadas
        final featureKey = '${res.source}_access';
        if (user.blockedFeatures.contains(featureKey)) return false;

        // Reglas específicas por nivel de acceso
        if ((res.source == 'tips_hacks' || res.source == 'la_nave') &&
            user.role != UserRole.TecnicoVerificado) {
          return false;
        }

        if (res.source == 'picás' && user.role == UserRole.TecnicoInvitado) {
          // Ejemplo de restricción específica si fuera necesaria
          return true;
        }

        return true;
      }).toList();

      state = AsyncValue.data(filteredResults);
    } catch (e, st) {
      state = AsyncValue.error('SEARCH PROTOCOL FAILURE: $e', st);
    }
  }
}

final semanticSearchProvider =
    StateNotifierProvider<
      SemanticSearchNotifier,
      AsyncValue<List<SemanticResult>>
    >((ref) {
      return SemanticSearchNotifier(ref);
    });
