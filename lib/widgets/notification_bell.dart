import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/notification_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/notification_providers.dart';
import 'package:intl/intl.dart';

/// Campanita de notificaciones estilo Facebook.
/// Muestra un badge con la cantidad de no leídas y un dropdown con la lista.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  final _overlayKey = GlobalKey();

  int? _localUnreadOverride;

  void _showNotificationsPanel() {
    final user = ref.read(authProvider).valueOrNull;
    final notifications = ref.read(appNotificationsProvider).valueOrNull ?? [];

    // Marcar todas como leídas al abrir el panel
    if (user != null) {
      markAllNotificationsAsRead(user.id);
      // Optimización: Limpiamos localmente para que el badge desaparezca YA.
      setState(() => _localUnreadOverride = 0);
    }

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _NotificationOverlay(
        notifications: notifications,
        offset: offset,
        screenWidth: screenWidth,
        bellWidth: renderBox.size.width,
        onDismiss: () => entry.remove(),
        onTap: (notification) {
          entry.remove();
          _navigateTo(notification);
        },
      ),
    );
    overlay.insert(entry);
  }

  void _navigateTo(AppNotification notification) {
    if (notification.routeName != null) {
      markNotificationAsRead(notification.id);
      Navigator.pushNamed(
        context,
        notification.routeName!,
        arguments: notification.routeArg,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverUnreadCount = ref.watch(unreadNotificationCountProvider);
    // Si tenemos un override local (0), lo usamos hasta que el server también sea 0.
    final unreadCount = (_localUnreadOverride != null && serverUnreadCount > 0)
        ? _localUnreadOverride!
        : serverUnreadCount;

    // Si el server ya llegó a 0, reseteamos el override.
    if (serverUnreadCount == 0 && _localUnreadOverride != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _localUnreadOverride = null);
      });
    }

    return GestureDetector(
      key: _overlayKey,
      onTap: _showNotificationsPanel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              unreadCount > 0
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              color: unreadCount > 0 ? Colors.greenAccent : Colors.white38,
              size: 22,
            ),
            if (unreadCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent,
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OVERLAY DEL PANEL DE NOTIFICACIONES (estilo Facebook dropdown)
// ---------------------------------------------------------------------------

class _NotificationOverlay extends StatelessWidget {
  final List<AppNotification> notifications;
  final Offset offset;
  final double screenWidth;
  final double bellWidth;
  final VoidCallback onDismiss;
  final ValueChanged<AppNotification> onTap;

  const _NotificationOverlay({
    required this.notifications,
    required this.offset,
    required this.screenWidth,
    required this.bellWidth,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Calcular posición del panel: anclado debajo de la campanita, alineado a la derecha
    const panelWidth = 320.0;
    final right = screenWidth - offset.dx - bellWidth - 8;
    final top = offset.dy + 36;

    return Stack(
      children: [
        // Backdrop transparente para cerrar al tocar fuera
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.translucent,
          child: Container(color: Colors.transparent),
        ),
        // Panel de notificaciones
        Positioned(
          top: top,
          right: right.clamp(8.0, screenWidth - panelWidth - 8),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: panelWidth,
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.greenAccent.withOpacity(0.1),
                        ),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.notifications,
                          color: Colors.greenAccent,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Notificaciones',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            fontFamily: 'Courier',
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Lista de notificaciones
                  if (notifications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Sin notificaciones\npor ahora, colega.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                          fontFamily: 'Courier',
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: notifications.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: Colors.white.withOpacity(0.05),
                        ),
                        itemBuilder: (context, index) {
                          final n = notifications[index];
                          return _NotificationTile(
                            notification: n,
                            onTap: () => onTap(n),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TILE INDIVIDUAL DE NOTIFICACIÓN
// ---------------------------------------------------------------------------

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(notification.createdAt);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: notification.isRead
            ? Colors.transparent
            : Colors.greenAccent.withOpacity(0.03),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Emoji icon
            Text(notification.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, height: 1.3),
                      children: [
                        TextSpan(
                          text: notification.sourceUserName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: notification.isRead
                                ? Colors.white54
                                : Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: ' ${notification.title}',
                          style: TextStyle(
                            color: notification.isRead
                                ? Colors.white38
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (notification.body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        notification.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: notification.isRead
                              ? Colors.white24
                              : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      color: notification.isRead
                          ? Colors.white24
                          : Colors.greenAccent.withOpacity(0.6),
                      fontSize: 10,
                      fontFamily: 'Courier',
                    ),
                  ),
                ],
              ),
            ),
            // Dot indicator para no leídas
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 6, top: 4),
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return DateFormat('dd/MM').format(date);
  }
}
