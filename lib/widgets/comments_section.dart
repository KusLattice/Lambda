import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/comment_model.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/comment_provider.dart';
import 'package:lambda_app/services/notification_service.dart';
import 'package:lambda_app/widgets/verification_dialog.dart';

/// Widget reutilizable de sección de comentarios.
/// Se puede insertar en cualquier bottom sheet de detalle de post.
///
/// Parámetros:
/// - [postId]: ID del documento padre en Firestore.
/// - [collectionName]: nombre de la colección padre (ej. 'food_tracker').
/// - [postOwnerId]: ID del autor del post (para la notificación de comentario nuevo).
/// - [accentColor]: color temático de la sección donde se usa.
class CommentsSection extends ConsumerStatefulWidget {
  final String postId;
  final String collectionName;
  final String postOwnerId;
  final String postTitle; // Para el cuerpo de la notificación
  final String postRouteName; // Para que la notificación navegue al post
  final Color accentColor;

  const CommentsSection({
    super.key,
    required this.postId,
    required this.collectionName,
    required this.postOwnerId,
    required this.postTitle,
    required this.postRouteName,
    required this.accentColor,
  });

  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendComment(User currentUser) async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final comment = PostComment(
        id: '',
        postId: widget.postId,
        authorId: currentUser.id,
        authorNickname: (currentUser.apodo?.isNotEmpty == true)
            ? currentUser.apodo!
            : currentUser.nombre,
        authorFotoUrl: currentUser.fotoUrl,
        body: body,
        createdAt: DateTime.now(),
      );

      await CommentService.addComment(
        collectionName: widget.collectionName,
        postId: widget.postId,
        comment: comment,
      );

      _controller.clear();

      // Notificar al autor del post si es diferente al comentador
      if (widget.postOwnerId != currentUser.id) {
        await NotificationService.notifyComment(
          targetUserId: widget.postOwnerId,
          sourceUserId: currentUser.id,
          sourceUserName: comment.authorNickname,
          postTitle: widget.postTitle,
          routeName: widget.postRouteName,
          postId: widget.postId,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar comentario: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await CommentService.deleteComment(
        collectionName: widget.collectionName,
        postId: widget.postId,
        commentId: commentId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al borrar comentario: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).valueOrNull;
    final isGuest = currentUser?.role == UserRole.TecnicoInvitado;
    final commentsAsync = ref.watch(
      commentsProvider((
        postId: widget.postId,
        collectionName: widget.collectionName,
      )),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.white10),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.comment_outlined, color: widget.accentColor, size: 18),
            const SizedBox(width: 8),
            Text(
              'COMENTARIOS',
              style: TextStyle(
                color: widget.accentColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                fontFamily: 'Courier',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Lista de comentarios
        commentsAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.accentColor,
                ),
              ),
            ),
          ),
          error: (err, _) => Text(
            'Error cargando comentarios.',
            style: TextStyle(color: Colors.red.shade300, fontSize: 12),
          ),
          data: (comments) {
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Sé el primero en comentar.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              );
            }
            return Column(
              children: comments
                  .map(
                    (c) => _CommentTile(
                      comment: c,
                      currentUser: currentUser,
                      accentColor: widget.accentColor,
                      collectionName: widget.collectionName,
                      postId: widget.postId,
                      onDelete: () => _deleteComment(c.id),
                    ),
                  )
                  .toList(),
            );
          },
        ),

        // Caja de texto para nuevo comentario (solo si está autenticado)
        if (currentUser != null) ...[
          const SizedBox(height: 16),
          if (isGuest)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Sólo los usuarios verificados pueden comentar.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const VerificationDialog(),
                      );
                    },
                    icon: const Icon(Icons.verified_user_outlined, size: 18),
                    label: const Text('VERIFÍCAME'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[850],
                  backgroundImage: currentUser.fotoUrl != null
                      ? NetworkImage(currentUser.fotoUrl!)
                      : null,
                  child: currentUser.fotoUrl == null
                      ? Icon(Icons.person, color: widget.accentColor, size: 16)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: null,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Escribe un comentario...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: widget.accentColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isSending
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.accentColor,
                        ),
                      )
                    : GestureDetector(
                        onTap: () => _sendComment(currentUser),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: widget.accentColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.black,
                            size: 16,
                          ),
                        ),
                      ),
              ],
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tile individual de comentario (con reacciones)
// ---------------------------------------------------------------------------

class _CommentTile extends ConsumerStatefulWidget {
  final PostComment comment;
  final User? currentUser;
  final Color accentColor;
  final String collectionName;
  final String postId;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    required this.currentUser,
    required this.accentColor,
    required this.collectionName,
    required this.postId,
    required this.onDelete,
  });

  @override
  ConsumerState<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<_CommentTile>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _aniCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _aniCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scaleAnim = CurvedAnimation(parent: _aniCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _removeOverlay();
    _aniCtrl.dispose();
    super.dispose();
  }

  bool get _canDelete {
    final user = widget.currentUser;
    if (user == null) return false;
    return user.id == widget.comment.authorId || user.isAdmin;
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showReactionPicker(BuildContext context) {
    if (widget.currentUser == null) return;
    HapticFeedback.mediumImpact();
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Tap fuera para cerrar
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeOverlay,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: offset.dx,
            top: offset.dy - 60,
            child: ScaleTransition(
              scale: _scaleAnim,
              alignment: Alignment.bottomLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: widget.accentColor.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: kLambdaReactions.map((r) {
                      final key = r['key']!;
                      final emoji = r['emoji']!;
                      final hasReacted = widget.comment.hasReacted(
                        key,
                        widget.currentUser!.id,
                      );
                      return GestureDetector(
                        onTap: () {
                          _removeOverlay();
                          CommentService.toggleReaction(
                            collectionName: widget.collectionName,
                            postId: widget.postId,
                            commentId: widget.comment.id,
                            reactionKey: key,
                            userId: widget.currentUser!.id,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: hasReacted
                                ? widget.accentColor.withValues(alpha: 0.2)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            emoji,
                            style: TextStyle(
                              fontSize: hasReacted ? 22 : 20,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _aniCtrl.forward();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) _aniCtrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final accentColor = widget.accentColor;

    // Filtrar reacciones con al menos 1 voto
    final activeReactions = kLambdaReactions.where(
      (r) => (comment.reactions[r['key']] ?? []).isNotEmpty,
    ).toList();

    return GestureDetector(
      onLongPress: () => _showReactionPicker(context),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey[850],
              backgroundImage: comment.authorFotoUrl != null
                  ? NetworkImage(comment.authorFotoUrl!)
                  : null,
              child: comment.authorFotoUrl == null
                  ? Icon(Icons.person, color: accentColor, size: 14)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                comment.authorNickname,
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              _formatDate(comment.createdAt),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                            if (_canDelete) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: widget.onDelete,
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white24,
                                  size: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          comment.body,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Fila de reacciones activas
                  if (activeReactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 8),
                      child: Wrap(
                        spacing: 6,
                        children: activeReactions.map((r) {
                          final key = r['key']!;
                          final emoji = r['emoji']!;
                          final count = comment.reactionCount(key);
                          final iMine = widget.currentUser != null &&
                              comment.hasReacted(key, widget.currentUser!.id);
                          return GestureDetector(
                            onTap: widget.currentUser == null
                                ? null
                                : () => CommentService.toggleReaction(
                                      collectionName: widget.collectionName,
                                      postId: widget.postId,
                                      commentId: comment.id,
                                      reactionKey: key,
                                      userId: widget.currentUser!.id,
                                    ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: iMine
                                    ? accentColor.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: iMine
                                      ? accentColor.withValues(alpha: 0.5)
                                      : Colors.white12,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(emoji,
                                      style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$count',
                                    style: TextStyle(
                                      color: iMine
                                          ? accentColor
                                          : Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // Hint de long press si no hay reacciones
                  if (activeReactions.isEmpty && widget.currentUser != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 8),
                      child: Text(
                        'mantén presionado para reaccionar',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.15),
                          fontSize: 9,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
