import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lambda_app/utils/image_utils.dart';
import 'package:intl/intl.dart';
import 'package:lambda_app/models/message_model.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/messaging_provider.dart';

import 'package:lambda_app/screens/public_profile_screen.dart';
import 'package:lambda_app/widgets/grid_background.dart';
import 'package:lambda_app/widgets/video_player_widget.dart';

/// Pantalla de conversación de chat entre dos usuarios.
/// Accedida desde MailScreen al tocar una conversación o un contacto.
class ChatConversationScreen extends ConsumerStatefulWidget {
  static const String routeName = '/chat-conversation';

  /// ID del otro participante del chat
  final String otherUserId;

  /// Nombre a mostrar del otro participante
  final String otherUserName;

  /// Foto del otro participante (opcional)
  final String? otherUserFotoUrl;

  /// Si es true, el chat se maneja bajo la identidad system_admin (solo para admins)
  final bool isSystemThread;

  /// ID del chat (opcional, si ya se conoce)
  final String? chatId;

  const ChatConversationScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserFotoUrl,
    this.isSystemThread = false,
    this.chatId,
  });

  @override
  ConsumerState<ChatConversationScreen> createState() =>
      _ChatConversationScreenState();
}

class _ChatConversationScreenState
    extends ConsumerState<ChatConversationScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showEmojiPanel = false;
  bool _isSending = false;
  String? _myUserId;

  /// Emojis frecuentes para el panel — sin dependencias externas
  static const List<String> _frequentEmojis = [
    '😂',
    '❤️',
    '👍',
    '🙌',
    '😎',
    '🔥',
    '✅',
    '💯',
    '🤙',
    '😅',
    '🤔',
    '👀',
    '🛠️',
    '📡',
    '📶',
    '🔧',
    '⚡',
    '🌐',
    '📱',
    '💻',
    '🎯',
    '🚀',
    '🔗',
    '🗂️',
    '📝',
    '🔒',
    '🛡️',
    '🧰',
    '🤓',
    '😤',
    '😬',
    '🤡',
    '💀',
    '👻',
    '🤖',
    '🐛',
    '🎉',
    '🥳',
    '🤦',
    '🔕',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = ref.read(authProvider).valueOrNull;
      if (me != null) {
        final isAdmin =
            me.role == UserRole.Admin || me.role == UserRole.SuperAdmin;

        // Identidad local para construir el chatId de envío
        // Si el otro es el sistema, yo soy humano. Si el otro es humano y yo admin, soy el sistema.
        final localId = (widget.isSystemThread &&
                isAdmin &&
                widget.otherUserId != 'system_admin')
            ? 'system_admin'
            : me.id;

        // Usamos el chatId canónico basado en estos dos participantes
        final chatId = Message.buildChatId(localId, widget.otherUserId);
        ref.read(messagingProvider).markChatMessagesAsRead(chatId);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _controller.clear();
    try {
      final me = ref.read(authProvider).valueOrNull;
      if (me == null) return;
      final isAdmin =
          me.role == UserRole.Admin || me.role == UserRole.SuperAdmin;
      final useSystemIdentity = widget.isSystemThread &&
          isAdmin &&
          widget.otherUserId != 'system_admin';

      await ref.read(messagingProvider).sendChatMessage(
            receiverId: widget.otherUserId,
            body: body,
            senderIdOverride: useSystemIdentity ? 'system_admin' : null,
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendImage() async {
    final picked = await LambdaImagePicker.pickSingleImage(context);
    if (picked == null) return;

    setState(() => _isSending = true);
    try {
      final me = ref.read(authProvider).valueOrNull;
      if (me == null) return;
      final isAdmin =
          me.role == UserRole.Admin || me.role == UserRole.SuperAdmin;
      final useSystemIdentity = widget.isSystemThread &&
          isAdmin &&
          widget.otherUserId != 'system_admin';

      await ref.read(messagingProvider).sendChatMessage(
            receiverId: widget.otherUserId,
            body: '',
            images: [File(picked.path)],
            senderIdOverride: useSystemIdentity ? 'system_admin' : null,
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error enviando imagen: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendVideo() async {
    final picked = await LambdaImagePicker.pickVideo(context);
    if (picked == null) return;

    setState(() => _isSending = true);
    try {
      final me = ref.read(authProvider).valueOrNull;
      if (me == null) return;
      final isAdmin =
          me.role == UserRole.Admin || me.role == UserRole.SuperAdmin;
      final useSystemIdentity = widget.isSystemThread &&
          isAdmin &&
          widget.otherUserId != 'system_admin';

      await ref.read(messagingProvider).sendChatMessage(
            receiverId: widget.otherUserId,
            body: '',
            videoFiles: [File(picked.path)],
            senderIdOverride: useSystemIdentity ? 'system_admin' : null,
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error enviando video: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _viewImageFullScreen(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construye el título del AppBar.
  /// Si el usuario tiene permiso de ver el perfil (contacto o Admin),
  /// el Row es clicable y navega a [PublicProfileScreen].
  Widget _buildAppBarTitle(BuildContext context, user) {
    // Regla de acceso al perfil:
    // - El otro usuario está en la lista de contactos del usuario actual, O
    // - El usuario actual es Admin o SuperAdmin.
    final canViewProfile =
        user != null &&
        widget.otherUserId != 'system_admin' &&
        (user.contactIds.contains(widget.otherUserId) ||
            user.role == UserRole.Admin ||
            user.role == UserRole.SuperAdmin);

    final isSystem = widget.otherUserId == 'system_admin';

    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: isSystem
          ? Colors.amber.withValues(alpha: 0.1)
          : Colors.grey[850],
      backgroundImage: widget.otherUserFotoUrl != null
          ? NetworkImage(widget.otherUserFotoUrl!)
          : null,
      child: widget.otherUserFotoUrl == null
          ? Icon(
              isSystem ? Icons.shield : Icons.person,
              color: isSystem ? Colors.amber : Colors.greenAccent,
              size: 18,
            )
          : null,
    );

    final nameRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatar,
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            widget.otherUserId == 'system_admin'
                ? 'ADMINISTRACIÓN λ'
                : widget.otherUserName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSystem ? Colors.amber : Colors.greenAccent,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              // Decoración underline cuando es enlace activo
              decoration: canViewProfile
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: Colors.greenAccent.withValues(alpha: 0.6),
            ),
          ),
        ),
        if (canViewProfile) ...[
          const SizedBox(width: 4),
          const Icon(Icons.open_in_new, color: Colors.greenAccent, size: 13),
        ],
      ],
    );

    if (!canViewProfile) return nameRow;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        PublicProfileScreen.routeName,
        arguments: widget.otherUserId,
      ),
      child: nameRow,
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).valueOrNull;
    _myUserId = me?.id;

    if (_myUserId == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
    }

    final currentUser = me!; // Seguro por el check anterior
    final isAdmin =
        currentUser.role == UserRole.Admin || currentUser.role == UserRole.SuperAdmin;
    // Identidad local dinámica
    final localId = (widget.isSystemThread &&
            isAdmin &&
            widget.otherUserId != 'system_admin')
        ? 'system_admin'
        : currentUser.id;

    // Priorizamos el chatId recibido (historial exacto) o lo construimos de forma canónica
    final chatId = widget.chatId ?? Message.buildChatId(localId, widget.otherUserId);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.greenAccent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.greenAccent),
          onPressed: () => Navigator.pop(context),
        ),
        title: _buildAppBarTitle(context, me),
      ),
      body: Stack(
        children: [
          const GridBackground(child: SizedBox.expand()),
          Column(
            children: [
              // Lista de mensajes
              Expanded(
                child: StreamBuilder<List<Message>>(
                  stream: ref
                      .read(messagingProvider)
                      .getChatMessagesStream(chatId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Colors.greenAccent,
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.signal_wifi_bad,
                              color: Colors.grey,
                              size: 48,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Error de señal.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    final messages = snapshot.data ?? [];
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          'Sin mensajes aún.\nSé el primero en transmitir. 📡',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white38,
                            fontFamily: 'Courier',
                          ),
                        ),
                      );
                    }

                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToBottom(),
                    );

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.senderId == localId;
                        return _ChatBubble(
                          message: msg,
                          isMe: isMe,
                          myUserRole: currentUser.role,
                          onImageTap: (url) =>
                              _viewImageFullScreen(context, url),
                          onVideoTap:
                              (url) {}, // Placeholder for future full screen?
                        );
                      },
                    );
                  },
                ),
              ),

              // Panel de emojis
              if (_showEmojiPanel)
                Container(
                  height: 200,
                  color: Colors.grey[900],
                  padding: const EdgeInsets.all(8),
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: _frequentEmojis.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () {
                          _controller.text += _frequentEmojis[index];
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: _controller.text.length),
                          );
                        },
                        child: Center(
                          child: Text(
                            _frequentEmojis[index],
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Barra de input (oculta si es Administración)
              if (widget.otherUserId != 'system_admin')
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                  color: Colors.black,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            setState(() => _showEmojiPanel = !_showEmojiPanel),
                        icon: Icon(
                          _showEmojiPanel
                              ? Icons.keyboard
                              : Icons.emoji_emotions_outlined,
                          color: Colors.greenAccent,
                        ),
                      ),
                      IconButton(
                        onPressed: _isSending ? null : _sendImage,
                        icon: Icon(
                          Icons.add_a_photo_outlined,
                          color: _isSending ? Colors.grey : Colors.greenAccent,
                        ),
                      ),
                      IconButton(
                        onPressed: _isSending ? null : _sendVideo,
                        icon: Icon(
                          Icons.video_call_outlined,
                          color: _isSending ? Colors.grey : Colors.greenAccent,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: Colors.white),
                          maxLines: null,
                          maxLength: 2000,
                          onTap: () {
                            if (_showEmojiPanel) {
                              setState(() => _showEmojiPanel = false);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Transmitir mensaje...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.07),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: Colors.greenAccent,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isSending
                          ? const SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.greenAccent,
                              ),
                            )
                          : GestureDetector(
                              onTap: _sendMessage,
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.send,
                                  color: Colors.black,
                                  size: 18,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Burbuja individual de chat (con long-press para eliminar)
// ---------------------------------------------------------------------------

class _ChatBubble extends ConsumerWidget {
  final Message message;
  final bool isMe;

  /// Rol del usuario actual (para permisos de Admin)
  final UserRole? myUserRole;
  final void Function(String url) onImageTap;
  final void Function(String url) onVideoTap;

  const _ChatBubble({
    required this.message,
    required this.isMe,
    required this.myUserRole,
    required this.onImageTap,
    required this.onVideoTap,
  });

  /// Solo el autor o un Admin/SuperAdmin puede mover a papelera.
  bool get _canDelete =>
      isMe || myUserRole == UserRole.Admin || myUserRole == UserRole.SuperAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = DateFormat('HH:mm').format(message.timestamp);
    final hasText = message.body.isNotEmpty;
    final hasImages = message.imageUrls.isNotEmpty;
    final hasVideos = message.videoUrls.isNotEmpty;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: _canDelete ? () => _showDeleteSheet(context, ref) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.greenAccent.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: isMe
                  ? Colors.greenAccent.withValues(alpha: 0.4)
                  : Colors.white24,
              width: 1,
            ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imágenes adjuntas
                if (hasImages) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: message.imageUrls.map((url) {
                      return GestureDetector(
                        onTap: () => onImageTap(url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            url,
                            width: 180,
                            height: 180,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                width: 180,
                                height: 180,
                                color: Colors.grey[850],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.greenAccent,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, _, _) => Container(
                              width: 180,
                              height: 180,
                              color: Colors.grey[850],
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (hasText || hasVideos) const SizedBox(height: 6),
                ],
                // Videos adjuntos
                if (hasVideos) ...[
                  ...message.videoUrls.map((url) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: IntegratedVideoPlayer(
                          videoUrl: url,
                          autoPlay: false,
                        ),
                      ),
                    );
                  }),
                  if (hasText) const SizedBox(height: 6),
                ],
                // Texto del mensaje
                if (hasText)
                  Text(
                    message.body,
                    style: TextStyle(
                      color: isMe
                          ? Colors.greenAccent.shade200
                          : Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                // Timestamp + leído
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isRead ? Icons.done_all : Icons.done,
                        size: 12,
                        color: message.isRead
                            ? Colors.greenAccent
                            : Colors.white38,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Bottom sheet que aparece al hacer long-press en una burbuja.
  void _showDeleteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Mover a Papelera',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Recuperable desde la sección Papelera',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref
                      .read(messagingProvider)
                      .deleteChatMessage(message.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Mensaje movido a la Papelera.'),
                        backgroundColor: Colors.grey,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
