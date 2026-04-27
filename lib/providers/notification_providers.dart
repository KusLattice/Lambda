import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/notification_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// BADGE DE CORREO NO LEÍDO 📬
// ---------------------------------------------------------------------------

/// Stream que emite la cantidad de mensajes no leídos en el inbox del usuario.
/// Usa receiverId + isRead como filtros mínimos para evitar necesitar un
/// Firestore composite index complejo. El filtro de 'labels' se hace client-side.
final unreadMailCountProvider = StreamProvider.autoDispose<int>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('messages')
      .where('receiverId', isEqualTo: user.id)
      .snapshots()
      .map(
        (snap) => snap.docs.where((doc) {
          final data = doc.data();
          if (data['isRead'] == true) return false;

          final labels = List<String>.from(data['labels'] ?? []);
          // Si el mensaje tiene ownerId, debe ser del usuario actual
          final ownerId = data['ownerId'] as String?;
          if (ownerId != null && ownerId != user.id) return false;

          // No debe estar en la papelera (global o privada)
          if (labels.contains('trash')) return false;
          if (labels.contains('trash_${user.id}')) return false;

          return true;
        }).length,
      );
});

// ---------------------------------------------------------------------------
// BADGE DE POSTS NUEVOS EN RANDOM 🎲
// ---------------------------------------------------------------------------

const _kLastSeenRandomKey = 'lastSeenRandomTimestamp';

/// StateProvider para manejar el timestamp de manera reactiva.
/// Se lee de SharedPreferences al inicio y se actualiza al entrar a Random.
final lastSeenRandomTimestampProvider = StateProvider<DateTime?>((ref) => null);

/// Inicializa el timestamp desde SharedPreferences. Se llama una vez al inicio.
Future<void> initLastSeenRandom(StateController<DateTime?> controller) async {
  final prefs = await SharedPreferences.getInstance();
  final millis = prefs.getInt(_kLastSeenRandomKey);
  if (millis != null) {
    controller.state = DateTime.fromMillisecondsSinceEpoch(millis);
  }
}

/// Guarda el timestamp actual como la última vez que se vio Random.
/// Actualiza tanto SharedPreferences como el StateProvider para reactividad.
Future<void> markRandomAsSeen(StateController<DateTime?> controller) async {
  final now = DateTime.now();
  controller.state = now;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastSeenRandomKey, now.millisecondsSinceEpoch);
}

/// Stream que indica si hay posts nuevos en Random desde la última visita.
final hasNewRandomPostsProvider = StreamProvider.autoDispose<bool>((
  ref,
) async* {
  final lastSeen = ref.watch(lastSeenRandomTimestampProvider);

  await for (final snap
      in FirebaseFirestore.instance
          .collection('random_board')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()) {
    if (snap.docs.isEmpty) {
      yield false;
      continue;
    }
    final latestPost = snap.docs.first;
    final createdAt = (latestPost.data()['timestamp'] as Timestamp?)?.toDate();
    if (createdAt == null) {
      yield false;
      continue;
    }
    if (lastSeen == null) {
      // Nunca visitó → hay posts nuevos
      yield true;
      continue;
    }
    yield createdAt.isAfter(lastSeen);
  }
});

// ---------------------------------------------------------------------------
// CAMPANITA DE NOTIFICACIONES 🔔
// ---------------------------------------------------------------------------

/// Stream de las últimas 30 notificaciones del usuario, ordenadas por fecha.
final appNotificationsProvider =
    StreamProvider.autoDispose<List<AppNotification>>((ref) {
      final user = ref.watch(authProvider).valueOrNull;
      if (user == null) return Stream.value([]);

      return FirebaseFirestore.instance
          .collection('notifications')
          .where('targetUserId', isEqualTo: user.id)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots()
          .map(
            (snap) =>
                snap.docs.map((d) => AppNotification.fromFirestore(d)).toList(),
          );
    });

/// Cuenta de notificaciones no leídas.
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(appNotificationsProvider).valueOrNull ?? [];
  return notifications.where((n) => !n.isRead).length;
});

/// Marca una notificación como leída en Firestore.
Future<void> markNotificationAsRead(String notificationId) async {
  await FirebaseFirestore.instance
      .collection('notifications')
      .doc(notificationId)
      .update({'isRead': true});
}

/// Marca todas las notificaciones de un usuario como leídas.
Future<void> markAllNotificationsAsRead(String userId) async {
  final batch = FirebaseFirestore.instance.batch();
  final unread = await FirebaseFirestore.instance
      .collection('notifications')
      .where('targetUserId', isEqualTo: userId)
      .where('isRead', isEqualTo: false)
      .get();
  for (final doc in unread.docs) {
    batch.update(doc.reference, {'isRead': true});
  }
  await batch.commit();
}
