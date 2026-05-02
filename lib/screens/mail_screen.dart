import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/message_model.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/messaging_provider.dart';
import 'package:lambda_app/screens/chat_conversation_screen.dart';
import 'package:lambda_app/widgets/grid_background.dart';
import 'package:intl/intl.dart';

class MailScreen extends ConsumerStatefulWidget {
  static const String routeName = '/mail';
  const MailScreen({super.key});

  @override
  ConsumerState<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends ConsumerState<MailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 3 tabs: Red | Conversaciones | Papelera
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'CORREO',
          style: TextStyle(
            fontFamily: 'Courier',
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Red'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chats'),
            Tab(icon: Icon(Icons.delete_outline), text: 'Papelera'),
          ],
        ),
        actions: const [],
      ),
      body: Stack(
        children: [
          const GridBackground(child: SizedBox.expand()),
          TabBarView(
            controller: _tabController,
            children: [
              const _ContactsList(),
              const _ConversationList(),
              _MessageList(label: 'trash'),
            ],
          ),
        ],
      ),
      // FAB: inicia nuevo chat desde la Red Galáctica
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _tabController.animateTo(0); // ir a Red para seleccionar contacto
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Selecciona un colega de tu Red Galáctica para chatear.',
                style: TextStyle(fontFamily: 'Courier'),
              ),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.grey,
            ),
          );
        },
        backgroundColor: Colors.greenAccent,
        child: const Icon(Icons.chat, color: Colors.black),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lista de conversaciones activas (nueva pestaña Chats)
// ---------------------------------------------------------------------------

class _ConversationList extends ConsumerWidget {
  const _ConversationList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).valueOrNull;
    if (me == null) return const SizedBox.shrink();

    return StreamBuilder<List<Message>>(
      stream: ref.read(messagingProvider).getChatConversationsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.greenAccent),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.settings_input_antenna,
                  color: Colors.grey,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Señal interrumpida.',
                  style: TextStyle(color: Colors.grey, fontFamily: 'Courier'),
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          );
        }

        final conversations = snapshot.data ?? [];

        if (conversations.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white24,
                  size: 64,
                ),
                SizedBox(height: 16),
                Text(
                  'Sin conversaciones.\nVe a Red Galáctica y contacta a un usuario.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final lastMsg = conversations[index];
            final isMe = lastMsg.senderId == me.id;
            final isAdmin = me.role == UserRole.Admin || me.role == UserRole.SuperAdmin;
            
            String otherUserId = isMe ? lastMsg.receiverId : lastMsg.senderId;

            // Si soy admin y estoy viendo un mensaje del sistema, el "otro" es el humano.
            if (isAdmin) {
              if (lastMsg.senderId == 'system_admin') {
                otherUserId = lastMsg.receiverId;
              } else if (lastMsg.receiverId == 'system_admin') {
                otherUserId = lastMsg.senderId;
              }
              
              // Si después de la lógica anterior resultara ser yo mismo (ej: yo envié a system_admin)
              // el interlocutor visual para el admin sigue siendo el sistema.
              if (otherUserId == me.id) {
                otherUserId = 'system_admin';
              }
            }
            
            final bool isSystemThread = lastMsg.senderId == 'system_admin' || lastMsg.receiverId == 'system_admin';

            // Cargar datos del otro usuario para el avatar y nombre
            return _ConversationTile(
              lastMessage: lastMsg,
              myUserId: me.id,
              otherUserId: otherUserId,
              isSystemThread: isSystemThread,
            );
          },
        );
      },
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  final Message lastMessage;
  final String myUserId;
  final String otherUserId;
  final bool isSystemThread;

  const _ConversationTile({
    required this.lastMessage,
    required this.myUserId,
    required this.otherUserId,
    this.isSystemThread = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = lastMessage.senderId == myUserId;
    final hasUnread = !isMe && !lastMessage.isRead;
    final time = DateFormat('dd/MM HH:mm').format(lastMessage.timestamp);

    // --- MANEJO ESTÁTICO DE ADMINISTRACIÓN λ ---
    // Bypasseamos la base de datos para system_admin para evitar cuelgues o errores de permisos.
    if (otherUserId == 'system_admin') {
      return _buildTile(
        context: context,
        ref: ref,
        displayName: 'ADMINISTRACIÓN λ',
        fotoUrl: null,
        isSystem: true,
        hasUnread: hasUnread,
        isMe: isMe,
        time: time,
        targetUserId: 'system_admin',
      );
    }

    // Cargar los datos del otro usuario (stream por ID)
    final otherUserAsync = ref.watch(userDocumentStreamProvider(otherUserId));

    return otherUserAsync.when(
      data: (doc) {
        final data = doc.data() as Map<String, dynamic>?;
        final otherUser = data != null ? User.fromMap(data, otherUserId) : null;

        String displayName = otherUserId; // Fallback
        if (otherUser != null) {
          if (otherUser.apodo != null && otherUser.apodo!.trim().isNotEmpty) {
            displayName = otherUser.apodo!;
          } else if (otherUser.nombre.trim().isNotEmpty) {
            displayName = otherUser.nombre;
          }
        }

        return _buildTile(
          context: context,
          ref: ref,
          displayName: displayName,
          fotoUrl: otherUser?.fotoUrl,
          isSystem: false,
          hasUnread: hasUnread,
          isMe: isMe,
          time: time,
          targetUserId: otherUserId,
        );
      },
      loading: () => _buildLoadingTile(),
      error: (e, st) => _buildErrorTile(otherUserId, e.toString()),
    );
  }

  Widget _buildLoadingTile() {
    return Card(
      color: Colors.grey[900]?.withValues(alpha: 0.8),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: const ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.white10,
          child: CircularProgressIndicator(
            color: Colors.greenAccent,
            strokeWidth: 2,
          ),
        ),
        title: Text('Cargando...', style: TextStyle(color: Colors.white54)),
      ),
    );
  }

  Widget _buildErrorTile(String userId, String error) {
    return Card(
      color: Colors.grey[900]?.withValues(alpha: 0.8),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.redAccent,
          child: Icon(Icons.error_outline, color: Colors.white),
        ),
        title: Text(userId, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          error,
          style: const TextStyle(color: Colors.redAccent, fontSize: 10),
        ),
      ),
    );
  }

  /// Helper que construye el Card común para el tile de conversación.
  Widget _buildTile({
    required BuildContext context,
    required WidgetRef ref,
    required String displayName,
    required String? fotoUrl,
    required bool isSystem,
    required bool hasUnread,
    required bool isMe,
    required String time,
    required String targetUserId,
  }) {
    final previewText =
        lastMessage.imageUrls.isNotEmpty && lastMessage.body.isEmpty
        ? '📷 Imagen'
        : (isMe
              ? '${String.fromCharCode(0x25B6)} ${lastMessage.body}'
              : lastMessage.body);

    return Card(
      clipBehavior: Clip.antiAlias, // Necesario para InkWell redondeado
      color: hasUnread
          ? Colors.greenAccent.withValues(alpha: 0.07)
          : Colors.grey[900]?.withValues(alpha: 0.8),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasUnread
            ? const BorderSide(color: Colors.greenAccent, width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          try {
            // Marcar como leído
            final chatId = lastMessage.chatId;
            if (chatId.isNotEmpty) {
              ref.read(messagingProvider).markChatMessagesAsRead(chatId);
            }

            // Navegar usando parámetros consistentes con main.dart
            Navigator.pushNamed(
              context,
              ChatConversationScreen.routeName,
              arguments: <String, dynamic>{
                'otherUserId': targetUserId,
                'otherUserName': displayName,
                'otherUserFotoUrl': fotoUrl,
                'isSystemThread': isSystemThread,
                'chatId': lastMessage.chatId,
              },
            );
          } catch (e) {
            debugPrint('Error navigating to chat: $e');
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: isSystem
                      ? Colors.amber.withValues(alpha: 0.1)
                      : Colors.grey[850],
                  backgroundImage: fotoUrl != null
                      ? NetworkImage(fotoUrl)
                      : null,
                  child: fotoUrl == null
                      ? Icon(
                          isSystem ? Icons.shield : Icons.person,
                          color: isSystem ? Colors.amber : Colors.greenAccent,
                          size: 24,
                        )
                      : null,
                ),
                if (hasUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              displayName,
              style: TextStyle(
                color: isSystem ? Colors.amber : Colors.white,
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                fontFamily: isSystem ? 'Courier' : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              previewText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread ? Colors.greenAccent : Colors.grey,
                fontSize: 13,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  tooltip: 'Eliminar conversación',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _confirmDelete(context, ref, displayName),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String displayName,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          '🗑️ Eliminar conversación',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Text(
          'Se moverán todos los mensajes con $displayName a la Papelera.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ELIMINAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await ref
          .read(messagingProvider)
          .deleteChatConversation(lastMessage.chatId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Conversación movida a Papelera.'),
            backgroundColor: Colors.grey[800],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Papelera: restaurar + eliminar definitivamente
// ---------------------------------------------------------------------------

class _MessageList extends ConsumerWidget {
  final String label;
  const _MessageList({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<List<Message>>(
      stream: ref.read(messagingProvider).getMessagesStream(label),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.greenAccent),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final messages = snapshot.data ?? [];
        final List<Message> filteredMessages;
        if (label == 'trash') {
          // Agrupar mensajes de chat por chatId para evitar duplicidad visual
          final Map<String, Message> grouped = {};
          final List<Message> nonChat = [];

          for (final m in messages) {
            if (m.chatId.isNotEmpty) {
              final existing = grouped[m.chatId];
              if (existing == null || m.timestamp.isAfter(existing.timestamp)) {
                grouped[m.chatId] = m;
              }
            } else {
              nonChat.add(m);
            }
          }
          filteredMessages = [...nonChat, ...grouped.values]
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        } else {
          filteredMessages = messages;
        }

        if (filteredMessages.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.white24,
                  size: 64,
                ),
                SizedBox(height: 12),
                Text(
                  'Papelera vacía.\nNada que lamentar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontFamily: 'Courier'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: filteredMessages.length,
          itemBuilder: (context, index) {
            final msg = filteredMessages[index];
            final hasImages = msg.imageUrls.isNotEmpty;
            final isChatMsg = msg.chatId.isNotEmpty;
            final isSystem = msg.senderId == 'system_admin';

            return FutureBuilder<DocumentSnapshot>(
              future: isSystem
                  ? null
                  : FirebaseFirestore.instance
                        .collection('users')
                        .doc(msg.senderId)
                        .get(),
              builder: (context, userSnap) {
                String senderName = msg.senderId;
                if (isSystem) {
                  senderName = 'ADMINISTRACIÓN λ';
                } else if (userSnap.hasData && userSnap.data!.exists) {
                  final data = userSnap.data!.data() as Map<String, dynamic>?;
                  senderName =
                      data?['apodo'] ?? data?['nombre'] ?? msg.senderId;
                }

                final preview = isChatMsg && label == 'trash'
                    ? '💬 Conversación completa'
                    : (hasImages && msg.body.isEmpty
                          ? '📷 ${msg.imageUrls.length} imagen(es)'
                          : msg.body.length > 50
                          ? '${msg.body.substring(0, 50)}…'
                          : msg.body.isEmpty
                          ? '(sin texto)'
                          : msg.body);

                return Card(
                  color: Colors.grey[900]?.withValues(alpha: 0.85),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSystem
                          ? Colors.greenAccent.withValues(alpha: 0.3)
                          : (isChatMsg
                                ? Colors.orangeAccent.withValues(alpha: 0.3)
                                : Colors.white12),
                    ),
                  ),
                  child: ListTile(
                    onTap: () {
                      // Diálogo táctico para leer el mensaje
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          title: Row(
                            children: [
                              Icon(
                                isSystem ? Icons.security : Icons.mail_outline,
                                color: isSystem
                                    ? Colors.greenAccent
                                    : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  msg.subject.isNotEmpty
                                      ? msg.subject.toUpperCase()
                                      : 'COMUNICADO',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontFamily: 'Courier',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DE: $senderName',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 11,
                                    fontFamily: 'Courier',
                                  ),
                                ),
                                const Divider(color: Colors.white10),
                                Text(
                                  msg.body,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'CERRAR',
                                style: TextStyle(color: Colors.greenAccent),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    leading: CircleAvatar(
                      backgroundColor: isSystem
                          ? Colors.green[900]
                          : (isChatMsg ? Colors.orange[900] : Colors.grey[800]),
                      child: Icon(
                        isSystem
                            ? Icons.security
                            : (isChatMsg ? Icons.chat_bubble : Icons.mail),
                        color: isSystem
                            ? Colors.greenAccent
                            : (isChatMsg
                                  ? Colors.orangeAccent
                                  : Colors.white54),
                        size: 18,
                      ),
                    ),
                    title: Text(
                      senderName,
                      style: TextStyle(
                        color: isSystem ? Colors.greenAccent : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Courier',
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          DateFormat('dd/MM HH:mm').format(msg.timestamp),
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    trailing: label == 'trash'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.restore,
                                  color: Colors.blueAccent,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  if (isChatMsg) {
                                    await ref
                                        .read(messagingProvider)
                                        .restoreChatConversation(msg.chatId);
                                  } else {
                                    await ref
                                        .read(messagingProvider)
                                        .restoreMessageFromTrash(msg.id);
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_forever,
                                  color: Colors.redAccent,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _confirmPermanentDelete(
                                  context,
                                  ref,
                                  msg.id,
                                  chatId: isChatMsg ? msg.chatId : null,
                                ),
                              ),
                            ],
                          )
                        : const Icon(
                            Icons.chevron_right,
                            color: Colors.white24,
                            size: 16,
                          ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Diálogo de confirmación antes del borrado permanente.
  Future<void> _confirmPermanentDelete(
    BuildContext context,
    WidgetRef ref,
    String messageId, {
    String? chatId,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          '⚠️ Eliminar Definitivamente',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Text(
          chatId != null
              ? 'Esta acción es irreversible.\nSe eliminarán TODOS los mensajes de esta conversación para siempre.'
              : 'Esta acción es irreversible.\nEl mensaje desaparecerá para siempre.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ELIMINAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        if (chatId != null) {
          await ref
              .read(messagingProvider)
              .permanentlyDeleteChatConversation(chatId);
        } else {
          await ref
              .read(messagingProvider)
              .permanentlyDeleteMessage(messageId);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mensaje eliminado definitivamente.'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Red Galáctica: lista de contactos con acción de chat directo
// ---------------------------------------------------------------------------

class _ContactsList extends ConsumerWidget {
  const _ContactsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: ElevatedButton.icon(
            onPressed: () => _showAddContactDialog(context, ref),
            icon: const Icon(Icons.person_add, color: Colors.black),
            label: const Text(
              'AÑADIR A LA RED',
              style: TextStyle(color: Colors.black),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<User>>(
            stream: ref.read(messagingProvider).getContactsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.greenAccent),
                );
              }
              final contacts = snapshot.data ?? [];
              if (contacts.isEmpty) {
                return const Center(
                  child: Text(
                    'Red Galáctica vacía.\nAñade colegas con su ID o Apodo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  final isBlocked = user.blockedUsers.contains(contact.id);

                  return Card(
                    color: Colors.grey[900]?.withValues(alpha: 0.8),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: contact.fotoUrl != null
                            ? NetworkImage(contact.fotoUrl!)
                            : null,
                        child: contact.fotoUrl == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        contact.apodo ?? contact.nombre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        isBlocked ? 'BLOQUEADO' : contact.role.displayName,
                        style: TextStyle(
                          color: isBlocked ? Colors.redAccent : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      // Acción primaria: abrir chat directo
                      trailing: isBlocked
                          ? const Icon(
                              Icons.block,
                              color: Colors.redAccent,
                              size: 20,
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.chat_bubble,
                                color: Colors.greenAccent,
                              ),
                              tooltip: 'Chatear',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatConversationScreen(
                                      otherUserId: contact.id,
                                      otherUserName:
                                          contact.apodo ?? contact.nombre,
                                      otherUserFotoUrl: contact.fotoUrl,
                                    ),
                                  ),
                                );
                              },
                            ),
                      onTap: () =>
                          _showContactConsole(context, ref, contact, user),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddContactDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Añadir Colega',
          style: TextStyle(color: Colors.greenAccent),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'ID o Apodo del Usuario',
            labelStyle: TextStyle(color: Colors.grey),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final tech = await ref
                  .read(authProvider.notifier)
                  .findUserToContact(controller.text);
              if (tech != null) {
                await ref.read(messagingProvider).addContact(tech.id);
                if (context.mounted) Navigator.pop(context);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Usuario no encontrado'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }

  void _showContactConsole(
    BuildContext context,
    WidgetRef ref,
    User contact,
    User me,
  ) {
    final isBlocked = me.blockedUsers.contains(contact.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'CONSOLA TÁCTICA: ${(contact.apodo ?? contact.nombre).toUpperCase()}',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: Colors.greenAccent, height: 30),
            ListTile(
              leading: const Icon(Icons.chat_bubble, color: Colors.greenAccent),
              title: const Text(
                'ABRIR CHAT',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatConversationScreen(
                      otherUserId: contact.id,
                      otherUserName: contact.apodo ?? contact.nombre,
                      otherUserFotoUrl: contact.fotoUrl,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                isBlocked ? Icons.lock_open : Icons.block,
                color: isBlocked ? Colors.blueAccent : Colors.orangeAccent,
              ),
              title: Text(
                isBlocked ? 'DESBLOQUEAR USUARIO' : 'BLOQUEAR USUARIO',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () async {
                if (isBlocked) {
                  await ref.read(authProvider.notifier).unblockUser(contact.id);
                } else {
                  await ref.read(authProvider.notifier).blockUser(contact.id);
                }
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: Colors.redAccent),
              title: const Text(
                'ELIMINAR DE MI RED',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                await ref.read(authProvider.notifier).removeContact(contact.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
