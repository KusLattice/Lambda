import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';

class RecycleBinScreen extends ConsumerWidget {
  static const String routeName = '/recycle-bin';

  const RecycleBinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Papelera de Administrador'),
          backgroundColor: Colors.red[900]?.withOpacity(0.5),
          bottom: const TabBar(
            indicatorColor: Colors.redAccent,
            labelColor: Colors.redAccent,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Usuarios'),
              Tab(icon: Icon(Icons.forum), text: 'Posts'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUsersTab(context, ref),
            _buildPostsTab(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab(BuildContext context, WidgetRef ref) {
    // Reutilizamos el allUsersProvider (que asume trae a todos los usuarios, luego filtramos)
    final allUsersAsync = ref.watch(allUsersProvider);
    final authNotifier = ref.read(authProvider.notifier);

    return allUsersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      ),
      error: (err, stack) => Center(
        child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
      ),
      data: (users) {
        final deletedUsers = users.where((u) => u.isDeleted).toList();

        if (deletedUsers.isEmpty) {
          return const Center(
            child: Text(
              'La papelera está vacía.',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          itemCount: deletedUsers.length,
          itemBuilder: (context, index) {
            final targetUser = deletedUsers[index];
            final deletedAt = targetUser.deletedAt;

            int daysRemaining = 0;
            bool isPurgable = false;
            if (deletedAt != null) {
              final diff = DateTime.now().difference(deletedAt).inDays;
              daysRemaining = 3 - diff;
              if (daysRemaining < 0) {
                isPurgable = true;
                daysRemaining = 0;
              }
            }

            return Card(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Colors.redAccent, width: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.person_off, color: Colors.redAccent),
                title: Text(
                  targetUser.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  isPurgable
                      ? 'Tiempo expirado. Listo para purga final.'
                      : 'Eliminación final en $daysRemaining días.',
                  style: TextStyle(
                    color: isPurgable ? Colors.red : Colors.orangeAccent,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.restore,
                        color: Colors.greenAccent,
                      ),
                      tooltip: 'Restaurar Usuario',
                      onPressed: () async {
                        try {
                          await authNotifier.restoreUser(targetUser.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Usuario restaurado exitosamente.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.toString()),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 24),
                    // El botón de purga final elimina el doc de Firestore (permanente)
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      tooltip: 'Purgar (Irreversible)',
                      onPressed: () {
                        _showPurgeConfirmDialog(
                          context,
                          authNotifier,
                          targetUser,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPurgeConfirmDialog(
    BuildContext context,
    AuthStateNotifier authNotifier,
    User targetUser,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Confirmar Purga',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar a ${targetUser.nombre} de forma PERMANENTE? Esta acción no se puede deshacer.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                // Aquí usamos una función del notifier para purgar,
                // pero si no existe, la invocamos directamente a Firestore.
                await authNotifier.purgeUser(targetUser.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Usuario purgado permanentemente.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'PURGAR MUNDOS',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsTab(BuildContext context, WidgetRef ref) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('recycle_bin_posts')
          .orderBy('deletedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.redAccent),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'La papelera de posts está vacía.',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final reason = data['reason'] as String? ?? 'Sin justificación';
            final deletedAt = data['deletedAt'] as Timestamp?;
            final originalData = data['data'] as Map<String, dynamic>? ?? {};

            final text = originalData['text'] as String? ?? '';
            final imageUrl = originalData['imageUrl'] as String?;

            final dateStr = deletedAt != null
                ? DateFormat('MM/dd/yy HH:mm').format(deletedAt.toDate())
                : '';

            return Card(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Colors.redAccent, width: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Razón: $reason',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Contenido original:',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (imageUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: EdgeInsets.zero,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    InteractiveViewer(
                                      child: Image.network(imageUrl),
                                    ),
                                    Positioned(
                                      top: 40,
                                      right: 20,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Image.network(
                            imageUrl,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(
                            Icons.restore,
                            color: Colors.greenAccent,
                          ),
                          label: const Text(
                            'Restaurar',
                            style: TextStyle(color: Colors.greenAccent),
                          ),
                          onPressed: () => _restorePost(context, doc.id, data),
                        ),
                        const SizedBox(width: 24),
                        TextButton.icon(
                          icon: const Icon(
                            Icons.delete_forever,
                            color: Colors.red,
                          ),
                          label: const Text(
                            'Purgar',
                            style: TextStyle(color: Colors.red),
                          ),
                          onPressed: () =>
                              _showPurgePostDialog(context, doc.id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _restorePost(
    BuildContext context,
    String docId,
    Map<String, dynamic> recycleData,
  ) async {
    try {
      final originalPath = recycleData['originalPath'] as String;
      final isOP = recycleData['isOP'] as bool? ?? true;
      final originalData = recycleData['data'] as Map<String, dynamic>;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final originalRef = FirebaseFirestore.instance.doc(originalPath);
        final recycleRef = FirebaseFirestore.instance
            .collection('recycle_bin_posts')
            .doc(docId);

        tx.set(originalRef, originalData);
        tx.delete(recycleRef);

        if (!isOP) {
          final parts = originalPath.split('/');
          if (parts.length >= 4 &&
              parts[0] == 'random_board' &&
              parts[2] == 'replies') {
            final threadId = parts[1];
            final threadRef = FirebaseFirestore.instance
                .collection('random_board')
                .doc(threadId);
            tx.update(threadRef, {'replyCount': FieldValue.increment(1)});
          }
        }

        // Incrementar métricas globales de restauración
        final statsRef = FirebaseFirestore.instance
            .collection('metadata')
            .doc('board_stats');
        tx.update(statsRef, {'restoredPostsCount': FieldValue.increment(1)});
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post restaurado exitosamente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al restaurar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showPurgePostDialog(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Confirmar Purga de Post',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: const Text(
          '¿Eliminar este post permanentemente? Esta acción es irreversible.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await FirebaseFirestore.instance
                    .collection('recycle_bin_posts')
                    .doc(docId)
                    .delete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Post purgado.'),
                      backgroundColor: Colors.red,
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
            child: const Text('PURGAR', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
