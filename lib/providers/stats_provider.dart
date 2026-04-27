import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/providers/auth_provider.dart';

/// Modelo de datos para las estadísticas globales
class GlobalStatsData {
  final int totalUsers;
  final int activeUsers;
  final int adminUsers;
  final int superAdminUsers;
  final int guestUsers;
  final int activeBans;
  final int deletedUsers;
  final int marketPosts;
  final int foodPosts;
  final int lodgingPosts;
  final int randomThreads;
  final int hacks;
  final int visibleUsers;
  final int marcianUsers;
  final int navePosts;
  final int totalVisits;

  GlobalStatsData({
    required this.totalUsers,
    required this.activeUsers,
    required this.adminUsers,
    required this.superAdminUsers,
    required this.guestUsers,
    required this.activeBans,
    required this.deletedUsers,
    required this.marketPosts,
    required this.foodPosts,
    required this.lodgingPosts,
    required this.randomThreads,
    required this.hacks,
    required this.visibleUsers,
    required this.marcianUsers,
    required this.navePosts,
    required this.totalVisits,
  });

  factory GlobalStatsData.empty() => GlobalStatsData(
    totalUsers: 0,
    activeUsers: 0,
    adminUsers: 0,
    superAdminUsers: 0,
    guestUsers: 0,
    activeBans: 0,
    deletedUsers: 0,
    marketPosts: 0,
    foodPosts: 0,
    lodgingPosts: 0,
    randomThreads: 0,
    hacks: 0,
    visibleUsers: 0,
    marcianUsers: 0,
    navePosts: 0,
    totalVisits: 0,
  );
}

/// Proveedor del stream de estadísticas consolidadas
final statsProvider = StreamProvider<GlobalStatsData>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));

  // 1. Usuarios y Roles
  final usersStream = firestore.collection('users').snapshots();

  // Combinación reactiva liviana
  return usersStream.asyncMap((usersSnap) async {
    final docs = usersSnap.docs;

    // Filtros de usuarios locales (estos son livianos porque el snapshot ya los tiene)
    final totalUsers = docs.length;
    final activeUsers = docs.where((doc) {
      final lastActive = (doc.data()['lastActiveAt'] as Timestamp?)?.toDate();
      return lastActive != null && lastActive.isAfter(oneHourAgo);
    }).length;

    final adminUsers = docs
        .where((doc) => doc.data()['role'] == 'Admin')
        .length;
    final superAdminUsers = docs
        .where((doc) => doc.data()['role'] == 'SuperAdmin')
        .length;
    final guestUsers = docs
        .where((doc) => doc.data()['role'] == 'TecnicoInvitado')
        .length;
    final activeBans = docs
        .where((doc) => doc.data()['isBanned'] == true)
        .length;
    final deletedUsers = docs
        .where((doc) => doc.data()['isDeleted'] == true)
        .length;
    final visibleUsers = docs
        .where((doc) => doc.data()['isVisibleOnMap'] == true)
        .length;
    final marcianUsers = docs
        .where((doc) => doc.data()['canAccessVaultMartian'] == true)
        .length;

    // Obtener counts consolidados de metadata/app_stats (EVITA .count().get() masivos)
    final statsDoc = await firestore
        .collection('metadata')
        .doc('app_stats')
        .get();
    final statsData = statsDoc.data() ?? {};

    return GlobalStatsData(
      totalUsers: totalUsers,
      activeUsers: activeUsers,
      adminUsers: adminUsers,
      superAdminUsers: superAdminUsers,
      guestUsers: guestUsers,
      activeBans: activeBans,
      deletedUsers: deletedUsers,
      marketPosts: statsData['marketCount'] ?? 0,
      foodPosts: statsData['foodCount'] ?? 0,
      lodgingPosts: statsData['lodgingCount'] ?? 0,
      randomThreads: statsData['randomCount'] ?? 0,
      hacks: statsData['hacksCount'] ?? 0,
      visibleUsers: visibleUsers,
      marcianUsers: marcianUsers,
      navePosts: statsData['naveCount'] ?? 0,
      totalVisits: statsData['totalVisits'] ?? 0,
    );
  });
});
