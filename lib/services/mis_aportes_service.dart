import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lambda_app/models/contribution_item.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/config/modules_config.dart';

/// Servicio que agrega los aportes de un usuario desde todas las colecciones
/// de Firestore. Usa [Future.wait] para consultas en paralelo, evitando
/// waterfalls de red innecesarios.
///
/// Stateless: cada llamada a [fetchContributions] es independiente.
class MisAportesService {
  const MisAportesService();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Retorna todos los aportes del [user], validando sus permisos de acceso
  /// a cada módulo (rol + blockedFeatures).
  Future<List<ContributionItem>> fetchContributions(User user) async {
    final results = await Future.wait([
      _hasAccess(user, 'comida_access')
          ? _fetchFoodPosts(user.id)
          : Future.value(<ContributionItem>[]),
      _hasAccess(user, 'hospedaje_access')
          ? _fetchLodgingPosts(user.id)
          : Future.value(<ContributionItem>[]),
      _hasAccess(user, 'mercado_negro_access')
          ? _fetchMarketItems(user.id)
          : Future.value(<ContributionItem>[]),
      // Trucos no tiene llave de featureKey estándar de dashboard actual porque se movió al vault
      // pero se asume que si tiene acceso al Vault Lambda, puede ver sus aportes de 'Trucos'.
      user.canAccessVaultLambda
          ? _fetchSecretHacks(user.id)
          : Future.value(<ContributionItem>[]),
      // 'La Nave' originalmente referenciado como foro
      // Si no existe un featureKey estricto en kDashboardModules para "La Nave", asumimos acceso gral,
      // a menos de que esté explícitamente bloqueado.
      !user.blockedFeatures.contains('nave_access')
          ? _fetchNavePosts(user.id)
          : Future.value(<ContributionItem>[]),
      _hasAccess(user, 'fiber_cut_access')
          ? _fetchFiberCuts(user.id)
          : Future.value(<ContributionItem>[]),
      _hasAccess(user, 'chambas_access')
          ? _fetchChambas(user.id)
          : Future.value(<ContributionItem>[]),
    ]);

    return results.expand((list) => list).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Verifica si el usuario tiene acceso al módulo según `kDashboardModules` y sus `blockedFeatures`.
  bool _hasAccess(User user, String featureKey) {
    if (user.blockedFeatures.contains(featureKey)) return false;

    // Buscamos la definición del módulo por su featureKey
    try {
      final module = kDashboardModules.firstWhere(
        (m) => m.featureKey == featureKey,
      );
      // Validamos si el módulo tiene restricción de rol
      if (module.roleCheck != null && !module.roleCheck!(user)) {
        return false;
      }
      return true;
    } catch (_) {
      // Si no existe el módulo, por seguridad permitimos asumiendo que es un módulo no-listado
      // a menos que esté bloqueado explícitamente (checking inicial).
      return true;
    }
  }

  // ---------------------------------------------------------------------------
  // Queries privadas por colección
  // ---------------------------------------------------------------------------

  Future<List<ContributionItem>> _fetchFoodPosts(String userId) async {
    try {
      final snap = await _db
          .collection('foodPosts')
          .where('userId', isEqualTo: userId)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return ContributionItem(
          type: ContributionType.picaFood,
          title: (data['title'] as String?)?.trim().isNotEmpty == true
              ? data['title'] as String
              : 'Sin título',
          subtitle: data['locationName'] as String? ?? '',
          createdAt: _parseDate(data['createdAt']),
          sourceId: doc.id,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ContributionItem>> _fetchLodgingPosts(String userId) async {
    try {
      final snap = await _db
          .collection('lodgingPosts')
          .where('userId', isEqualTo: userId)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return ContributionItem(
          type: ContributionType.hospedaje,
          title: data['title'] as String? ?? 'Sin título',
          subtitle: data['locationName'] as String? ?? '',
          createdAt: _parseDate(data['createdAt']),
          sourceId: doc.id,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ContributionItem>> _fetchMarketItems(String userId) async {
    try {
      final snap = await _db
          .collection('marketItems')
          .where('sellerId', isEqualTo: userId)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return ContributionItem(
          type: ContributionType.mercado,
          title: data['title'] as String? ?? 'Sin título',
          subtitle: data['category'] as String? ?? '',
          createdAt: _parseDate(data['createdAt']),
          sourceId: doc.id,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ContributionItem>> _fetchSecretHacks(String userId) async {
    try {
      final snap = await _db
          .collection('secrets')
          .where('userId', isEqualTo: userId)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return ContributionItem(
          type: ContributionType.truco,
          title: data['title'] as String? ?? 'Sin título',
          subtitle: data['category'] as String? ?? '',
          createdAt: _parseDate(data['createdAt']),
          sourceId: doc.id,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ContributionItem>> _fetchNavePosts(String userId) async {
    try {
      final snap = await _db
          .collection('navePosts')
          .where('authorId', isEqualTo: userId)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return ContributionItem(
          type: ContributionType.laNave,
          title: data['title'] as String? ?? 'Sin título',
          subtitle: data['section'] as String? ?? '',
          createdAt: _parseDate(data['createdAt']),
          sourceId: doc.id,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ContributionItem>> _fetchFiberCuts(String userId) async {
    try {
      final snap = await _db
          .collection('fiberCutReports')
          .where('reporterId', isEqualTo: userId)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        final description = data['description'] as String?;
        final address = data['address'] as String?;
        final comuna = data['comuna'] as String?;
        return ContributionItem(
          type: ContributionType.falla,
          title: (description != null && description.isNotEmpty)
              ? description
              : 'Falla de Fibra',
          subtitle: address ?? comuna ?? '',
          createdAt: _parseDate(data['createdAt']),
          sourceId: doc.id,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ContributionItem>> _fetchChambas(String userId) async {
    try {
      final snap = await _db
          .collection('chambas')
          .where('authorId', isEqualTo: userId)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return ContributionItem(
          type: ContributionType.chamba,
          title: data['title'] as String? ?? 'Sin título',
          subtitle: data['type'] as String? ?? '',
          createdAt: _parseDate(data['timestamp']),
          sourceId: doc.id,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime(2000);
    return DateTime(2000);
  }
}
