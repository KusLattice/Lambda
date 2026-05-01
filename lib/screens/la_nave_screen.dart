import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/models/nave_post.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/nave_provider.dart';
import 'package:lambda_app/screens/create_nave_post_screen.dart';
import 'package:lambda_app/screens/map_screen.dart';
import 'package:lambda_app/screens/public_profile_screen.dart';
import 'package:lambda_app/widgets/comments_section.dart';
import 'package:lambda_app/widgets/image_zoom_gallery.dart';
import 'package:lambda_app/widgets/video_section.dart';

class LaNaveScreen extends ConsumerStatefulWidget {
  static const String routeName = '/la_nave';
  const LaNaveScreen({super.key});

  @override
  ConsumerState<LaNaveScreen> createState() => _LaNaveScreenState();
}

class _LaNaveScreenState extends ConsumerState<LaNaveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _sections = [
    'Deja tu cola',
    'Manos',
    'Foro',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _sections.length, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialPostId =
          ModalRoute.of(context)!.settings.arguments as String?;
      if (initialPostId != null) {
        _handleDeepLink(initialPostId);
      }
    });
  }

  void _handleDeepLink(String postId) async {
    // Buscar el post en todas las secciones
    for (int i = 0; i < _sections.length; i++) {
      // Aquí hay un pequeño dilema: los posts se cargan por stream
      // Pero el SearchService ya nos dio el resultado.
      // Podríamos intentar forzar la carga o simplemente cambiar de tab
      // y dejar que el feed lo encuentre si ya está cargado.

      // Pero para ser más precisos, necesitamos el post.
      // Por ahora, cambiaremos al tab si el post está en el feed actual.
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.valueOrNull;

    if (user?.canAccessVaultMartian != true) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Acceso Denegado',
            style: TextStyle(color: Colors.greenAccent),
          ),
          backgroundColor: Colors.black,
        ),
        backgroundColor: Colors.black,
        body: const Center(
          child: Text(
            'El marciano te juzga.\nNo tienes permiso para entrar a La Nave.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.greenAccent, fontSize: 18),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'LA NAVE (Foro)',
          style: TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        backgroundColor: Colors.grey[900],
        iconTheme: const IconThemeData(color: Colors.greenAccent),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Mapa de Operaciones',
            onPressed: () => Navigator.pushNamed(context, MapScreen.routeName),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.forum), text: 'Deja tu cola'),
            Tab(icon: Icon(Icons.handshake), text: 'Manos'),
            Tab(icon: Icon(Icons.help_outline), text: 'Foro'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _sections.map((section) {
          return _buildSectionFeed(section, user);
        }).toList(),
      ),
      floatingActionButton: user?.canAccessVaultMartian == true
          ? FloatingActionButton(
              backgroundColor: Colors.greenAccent,
              child: const Icon(Icons.add, color: Colors.black),
              onPressed: () {
                final currentSection = _sections[_tabController.index];
                Navigator.pushNamed(
                  context,
                  CreateNavePostScreen.routeName,
                  arguments: currentSection,
                );
              },
            )
          : null,
    );
  }

  Widget _buildSectionFeed(String section, User? user) {
    final postsAsync = ref.watch(navePostsProvider(section));

    return postsAsync.when(
      data: (posts) {
        if (posts.isEmpty) {
          return const Center(
            child: Text(
              'Aún no hay mensajes en esta sección de La Nave.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return ListView.builder(
          itemCount: posts.length,
          padding: const EdgeInsets.all(12),
          itemBuilder: (context, index) {
            final post = posts[index];

            // Deep Link logic inside builder
            final initialPostId =
                ModalRoute.of(context)!.settings.arguments as String?;
            if (initialPostId != null && post.id == initialPostId) {
              // Si el post está en este tab, nos aseguramos de estar en este tab
              final sectionIndex = _sections.indexOf(section);
              if (_tabController.index != sectionIndex) {
                Future.delayed(Duration.zero, () {
                  if (mounted) _tabController.animateTo(sectionIndex);
                });
              }

              // Mostrar detalle
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showPostDetails(context, post, user);
              });
            }

            return InkWell(
              onTap: () => _showPostDetails(context, post, user),
              child: _buildPostCard(post, user),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colors.greenAccent),
      ),
      error: (err, stack) => Center(
        child: Text(
          'Error galáctico: $err',
          style: const TextStyle(color: Colors.redAccent),
        ),
      ),
    );
  }

  Widget _buildPostCard(NavePost post, User? currentUser) {
    final isOwner = post.authorId == currentUser?.id;
    final isSuperAdmin = currentUser?.role == UserRole.SuperAdmin;
    final isAdmin = currentUser?.role == UserRole.Admin || isSuperAdmin;

    final canEdit = isOwner || isSuperAdmin;
    final canDelete = isOwner || isAdmin;

    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.black,
                  backgroundImage: post.authorFotoUrl != null
                      ? NetworkImage(post.authorFotoUrl!)
                      : null,
                  child: post.authorFotoUrl == null
                      ? const Icon(
                          Icons.person,
                          color: Colors.greenAccent,
                          size: 16,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(
                      context,
                      PublicProfileScreen.routeName,
                      arguments: post.authorId,
                    ),
                    child: Text(
                      post.authorNickname,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                Text(
                  _formatDate(post.createdAt),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (canEdit || canDelete)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canEdit)
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.white38,
                            size: 20,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CreateNavePostScreen(
                                  section: _sections[_tabController.index],
                                  initialPost: post,
                                ),
                              ),
                            );
                          },
                        ),
                      if (canDelete)
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.white38,
                            size: 20,
                          ),
                          onPressed: () => _confirmDelete(post),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              post.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(post.content, style: const TextStyle(color: Colors.white70)),
            if (post.location != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Colors.greenAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      post.address ?? 'Ubicación adjunta',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (post.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: PageView.builder(
                  itemCount: post.imageUrls.length,
                  itemBuilder: (context, i) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ImageZoomGallery(
                              imageUrls: post.imageUrls,
                              initialIndex: i,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            post.imageUrls[i],
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (post.imageUrls.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: Text(
                      'Desliza para ver más (${post.imageUrls.length} fotos)',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
            if (post.videoUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              VideoSection(videoUrls: post.videoUrls),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmDelete(NavePost post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Eliminar mensaje',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: const Text(
          '¿Estás seguro de que quieres borrar este mensaje permanentemente?',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await ref
            .read(naveProvider)
            .deletePost(post.id, post.imageUrls, post.videoUrls);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Mensaje eliminado.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showPostDetails(
    BuildContext context,
    NavePost post,
    User? currentUser,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Colors.greenAccent, width: 0.5),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[900],
                    backgroundImage: post.authorFotoUrl != null
                        ? NetworkImage(post.authorFotoUrl!)
                        : null,
                    child: post.authorFotoUrl == null
                        ? const Icon(Icons.person, color: Colors.greenAccent)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    post.authorNickname,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(post.createdAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                post.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                post.content,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
              if (post.imageUrls.isNotEmpty) ...[
                const SizedBox(height: 24),
                SizedBox(
                  height: 300,
                  child: PageView.builder(
                    itemCount: post.imageUrls.length,
                    itemBuilder: (context, i) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ImageZoomGallery(
                                imageUrls: post.imageUrls,
                                initialIndex: i,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              post.imageUrls[i],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (post.videoUrls.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Video Adjunto',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                VideoSection(videoUrls: post.videoUrls),
              ],
              const SizedBox(height: 24),
              // Comentarios del post de La Nave
              CommentsSection(
                postId: post.id,
                collectionName: 'nave_vault',
                postOwnerId: post.authorId,
                postTitle: post.title,
                postRouteName: LaNaveScreen.routeName,
                accentColor: Colors.greenAccent,
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}
