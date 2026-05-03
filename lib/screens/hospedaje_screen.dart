import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/providers/lodging_provider.dart';
import 'package:lambda_app/models/lodging_post_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/screens/create_lodging_post_screen.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/screens/public_profile_screen.dart';
import 'package:lambda_app/config/chile_regions.dart';
import 'package:lambda_app/widgets/antenna_rating.dart';
import 'package:lambda_app/widgets/comments_section.dart';
import 'package:lambda_app/widgets/video_section.dart';
import 'package:lambda_app/widgets/image_zoom_gallery.dart';
import 'package:lambda_app/providers/location_provider.dart';
import 'package:lambda_app/utils/geo_utils.dart';

class HospedajeScreen extends ConsumerStatefulWidget {
  static const String routeName = '/hospedaje';
  const HospedajeScreen({super.key});

  @override
  ConsumerState<HospedajeScreen> createState() => _HospedajeScreenState();
}

class _HospedajeScreenState extends ConsumerState<HospedajeScreen> {
  bool _hasOpenedInitialPost = false;
  String? _selectedRegion;

  @override
  Widget build(BuildContext context) {
    final lodgingsAsync = ref.watch(
      lodgingProvider,
    ); // Assuming lodgingProvider is the correct one, or if lodgingItemsProvider is new, it needs to be imported and used. Sticking to existing provider name.
    final currentUser = ref.watch(authProvider).valueOrNull;
    final userPosition = ref.watch(locationProvider).valueOrNull;
    final isGuest = currentUser == null || currentUser.role == UserRole.TecnicoInvitado;
    final initialPostId = ModalRoute.of(context)!.settings.arguments as String?;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text(
          'Hospedaje',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        actions: [
          PopupMenuButton<String?>(
            icon: Icon(
              _selectedRegion != null
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
              color: _selectedRegion != null
                  ? Colors.cyanAccent
                  : Colors.white54,
            ),
            tooltip: 'Filtrar por región',
            color: const Color(0xFF1E1E1E),
            onSelected: (value) => setState(() => _selectedRegion = value),
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(
                value: null,
                child: Text(
                  'Todas las regiones',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              ...kRegionNames.map(
                (r) => PopupMenuItem<String?>(
                  value: r,
                  child: Text(
                    r,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton(
              onPressed: () {
                Navigator.pushNamed(context, CreateLodgingPostScreen.routeName);
              },
              backgroundColor: Colors.greenAccent,
              child: const Icon(Icons.add, color: Colors.black, size: 28),
            ),
      body: lodgingsAsync.when(
        data: (posts) {
          if (posts.isEmpty) {
            return const Center(
              child: Text(
                'No hay hospedajes registrados.\n¡Recomienda o advierte de alguno!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          // Deep Link: Abrir post automáticamente si viene de búsqueda
          if (initialPostId != null && !_hasOpenedInitialPost) {
            final postToOpen = posts
                .where((p) => p.id == initialPostId)
                .firstOrNull;
            if (postToOpen != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_hasOpenedInitialPost) {
                  setState(() => _hasOpenedInitialPost = true);
                  _showPostDetails(context, postToOpen);
                }
              });
            }
          }

          var filteredPosts = _selectedRegion == null
              ? posts
              : posts
                    .where(
                      (p) => p.region == null || p.region == _selectedRegion,
                    )
                    .toList();

          // GPS Sorting: Only if no region filter is active and we have user position
          if (_selectedRegion == null && userPosition != null) {
            filteredPosts.sort((a, b) {
              if (a.coordinates == null && b.coordinates == null) return 0;
              if (a.coordinates == null) return 1;
              if (b.coordinates == null) return -1;

              final distA = haversineKm(
                userPosition.latitude,
                userPosition.longitude,
                a.coordinates!.latitude,
                a.coordinates!.longitude,
              );
              final distB = haversineKm(
                userPosition.latitude,
                userPosition.longitude,
                b.coordinates!.latitude,
                b.coordinates!.longitude,
              );
              return distA.compareTo(distB);
            });
          } else if (_selectedRegion == null) {
            // Default sort by createdAt desc if no GPS or region filter
            filteredPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }

          if (filteredPosts.isEmpty) {
            return Center(
              child: Text(
                _selectedRegion != null
                    ? 'No hay hospedajes en $_selectedRegion.'
                    : 'No hay hospedajes registrados.\n¡Recomienda o advierte de alguno!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filteredPosts.length,
            itemBuilder: (context, index) {
              final post = filteredPosts[index];
              return InkWell(
                onTap: () => _showPostDetails(context, post),
                child: Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.imageUrls.isNotEmpty)
                        Stack(
                          alignment: Alignment.bottomLeft,
                          children: [
                            Image.network(
                              post.imageUrls.first,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                            if (post.pricePerNight != null &&
                                post.pricePerNight! > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: const BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.only(
                                    topRight: Radius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  '\$${post.pricePerNight!.toStringAsFixed(0)} /noche',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    post.locationName.isNotEmpty
                                        ? post.locationName
                                        : 'Hospedaje',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (currentUser != null) ...[
                                  if (post.userId == currentUser.id ||
                                      currentUser.role == UserRole.SuperAdmin)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: Colors.blueAccent,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                CreateLodgingPostScreen(
                                                  initialPost: post,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  if (post.userId == currentUser.id ||
                                      currentUser.isAdmin)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _confirmDelete(context, post),
                                    ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person,
                                  color: Colors.cyanAccent,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    PublicProfileScreen.routeName,
                                    arguments: post.userId,
                                  ),
                                  child: Text(
                                    post.authorName,
                                    style: const TextStyle(
                                      color: Colors.cyanAccent,
                                      fontSize: 12,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Reemplazar estrellitas por mini antena con promedio
                                Row(
                                  children: [
                                    Icon(
                                      Icons.settings_input_antenna,
                                      color: post.ratingAverage > 0
                                          ? Colors.cyanAccent
                                          : Colors.white24,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      post.ratingAverage > 0
                                          ? post.ratingAverage.toStringAsFixed(
                                              1,
                                            )
                                          : 'Sin eval.',
                                      style: TextStyle(
                                        color: post.ratingAverage > 0
                                            ? Colors.cyanAccent
                                            : Colors.white38,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (userPosition != null && post.coordinates != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '📍 ${haversineKm(
                                  userPosition.latitude,
                                  userPosition.longitude,
                                  post.coordinates!.latitude,
                                  post.coordinates!.longitude,
                                ).toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
        error: (err, _) => Center(
          child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, LodgingPost post) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '¿Eliminar hospedaje?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Esta acción no se puede deshacer. ¿Seguro, pibe?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final currentUser = ref.read(authProvider).valueOrNull;
              if (currentUser != null) {
                ref
                    .read(lodgingProvider.notifier)
                    .deletePost(
                      post.id,
                      currentUser,
                      imageUrls: post.imageUrls,
                      videoUrls: post.videoUrls,
                    )
                    .catchError((e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: Colors.red,
                        ),
                      );
                    });
              }
            },
            child: const Text(
              'ELIMINAR',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showPostDetails(BuildContext context, LodgingPost post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (post.imageUrls.isNotEmpty)
                    SizedBox(
                      height: 300,
                      child: Stack(
                        children: [
                          PageView.builder(
                            itemCount: post.imageUrls.length,
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ImageZoomGallery(
                                        imageUrls: post.imageUrls,
                                        initialIndex: index,
                                      ),
                                    ),
                                  );
                                },
                                child: Hero(
                                  tag: 'lodging_${post.id}_$index',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      post.imageUrls[index],
                                      width: double.infinity,
                                      height: 300,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (post.imageUrls.length > 1)
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '1/${post.imageUrls.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  // Reproductor de video (si tiene)
                  if (post.videoUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    VideoSection(
                      videoUrls: post.videoUrls,
                      storagePath: 'lodging_media',
                      accentColor: Colors.cyanAccent,
                    ),
                  ],
                  Text(
                    post.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.person,
                        color: Colors.cyanAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context); // Cerrar bottom sheet
                          Navigator.pushNamed(
                            context,
                            PublicProfileScreen.routeName,
                            arguments: post.userId,
                          );
                        },
                        child: Text(
                          'Publicado por: ${post.authorName}',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.redAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          post.locationName.isNotEmpty
                              ? post.locationName
                              : 'Ubicación no especificada',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 10),
                  const Text(
                    'RESEÑA',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Courier',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    post.description.isNotEmpty
                        ? post.description
                        : 'Sin descripción.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (post.pricePerNight != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.greenAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Precio Estimado',
                            style: TextStyle(color: Colors.white70),
                          ),
                          Text(
                            '\$${post.pricePerNight!.toStringAsFixed(0)} / noche',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  // Rating tipo antena
                  AntennaRating(
                    postId: post.id,
                    collectionName: 'lodging_tracker',
                    accentColor: Colors.cyanAccent,
                    currentAverage: post.ratingAverage,
                    ratingCount: post.ratingCount,
                  ),
                  const SizedBox(height: 8),
                  // Sección de comentarios
                  CommentsSection(
                    postId: post.id,
                    collectionName: 'lodging_tracker',
                    postOwnerId: post.userId,
                    postTitle: post.title.isNotEmpty
                        ? post.title
                        : post.locationName,
                    postRouteName: HospedajeScreen.routeName,
                    accentColor: Colors.cyanAccent,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
