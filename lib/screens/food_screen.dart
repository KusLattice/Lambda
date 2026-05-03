import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/providers/food_provider.dart';
import 'package:lambda_app/models/food_post_model.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/screens/create_food_post_screen.dart';
import 'package:intl/intl.dart';
import 'package:lambda_app/screens/public_profile_screen.dart';
import 'package:lambda_app/config/chile_regions.dart';
import 'package:lambda_app/widgets/antenna_rating.dart';
import 'package:lambda_app/widgets/comments_section.dart';
import 'package:lambda_app/widgets/video_section.dart';
import 'package:lambda_app/widgets/image_zoom_gallery.dart';
import 'package:lambda_app/providers/location_provider.dart';
import 'package:lambda_app/utils/geo_utils.dart';

class FoodScreen extends ConsumerStatefulWidget {
  static const String routeName = '/food';
  const FoodScreen({super.key});

  @override
  ConsumerState<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends ConsumerState<FoodScreen> {
  bool _hasOpenedInitialPost = false;
  String? _selectedRegion;
  String? _selectedComuna;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foodState = ref.watch(foodProvider);
    final currentUser = ref.watch(authProvider).valueOrNull;
    final userPosition = ref.watch(locationProvider).valueOrNull;
    final isGuest = currentUser?.role == UserRole.TecnicoInvitado;
    final initialPostId = ModalRoute.of(context)!.settings.arguments as String?;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        appBar: AppBar(
          title: const Text(
            'Picás',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.orangeAccent),
          actions: [
            // Filtro por Región
            PopupMenuButton<String?>(
              icon: Icon(
                _selectedRegion != null
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
                color: _selectedRegion != null
                    ? Colors.orangeAccent
                    : Colors.white54,
              ),
              tooltip: 'Filtrar por región',
              color: const Color(0xFF1E1E1E),
              onSelected: (value) => setState(() {
                _selectedRegion = value;
                _selectedComuna = null; // Reset comuna al cambiar región
              }),
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
            // Filtro por Comuna (solo si hay región seleccionada)
            if (_selectedRegion != null)
              PopupMenuButton<String?>(
                icon: Icon(
                  _selectedComuna != null
                      ? Icons.location_city
                      : Icons.location_city_outlined,
                  color: _selectedComuna != null
                      ? Colors.orangeAccent
                      : Colors.white54,
                  size: 20,
                ),
                tooltip: 'Filtrar por comuna',
                color: const Color(0xFF1E1E1E),
                onSelected: (value) => setState(() => _selectedComuna = value),
                itemBuilder: (context) => [
                  const PopupMenuItem<String?>(
                    value: null,
                    child: Text(
                      'Todas las comunas',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  ...(kChileRegions[_selectedRegion] ?? []).map(
                    (c) => PopupMenuItem<String?>(
                      value: c,
                      child: Text(
                        c,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
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
                onPressed: () =>
                    Navigator.pushNamed(context, CreateFoodPostScreen.routeName),
                backgroundColor: Colors.orangeAccent,
                child: const Icon(Icons.add_a_photo, color: Colors.black),
              ),
        body: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: foodState.when(
        data: (posts) {
          if (posts.isEmpty) {
            return const Center(
              child: Text(
                'No hay picás registradas.\n¡Aporta con lo tuyo!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          // Deep Link
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

          var filteredPosts = posts.where((p) {
            // Región/Comuna Filter
            if (_selectedRegion != null &&
                p.region != null &&
                p.region != _selectedRegion) {
              return false;
            }
            if (_selectedComuna != null &&
                p.comuna != null &&
                p.comuna != _selectedComuna) {
              return false;
            }

            // Search Query Filter
            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              final inTitle = p.title.toLowerCase().contains(query);
              final inLocation = p.locationName.toLowerCase().contains(query);
              final inDescription = p.description.toLowerCase().contains(query);
              if (!inTitle && !inLocation && !inDescription) {
                return false;
              }
            }
            return true;
          }).toList();

          // GPS Sorting: Only if no filters are active and we have user position
          if (_selectedRegion == null && _selectedComuna == null && userPosition != null) {
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
          } else if (_selectedRegion == null && _selectedComuna == null) {
            // Default sort by createdAt desc if no GPS or filters
            filteredPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }

          if (filteredPosts.isEmpty) {
            return Center(
              child: Text(
                _selectedRegion != null
                    ? 'No hay picás en ${_selectedComuna ?? _selectedRegion}.'
                    : 'No hay picás registradas.\n¡Aporta con lo tuyo!',
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
                        SizedBox(
                          height: 200,
                          child: Stack(
                            children: [
                              PageView.builder(
                                itemCount: post.imageUrls.length,
                                itemBuilder: (context, i) {
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ImageZoomGallery(
                                                imageUrls: post.imageUrls,
                                                initialIndex: i,
                                              ),
                                        ),
                                      );
                                    },
                                    child: Image.network(
                                      post.imageUrls[i],
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                },
                              ),
                              if (post.imageUrls.length > 1)
                                Positioned(
                                  bottom: 8,
                                  right: 8,
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
                      if (post.videoUrls.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: VideoSection(
                            videoUrls: post.videoUrls,
                            storagePath: 'food_media',
                            accentColor: Colors.orangeAccent,
                          ),
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
                                        : post.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
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
                                        Icons.edit,
                                        color: Colors.blueAccent,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                CreateFoodPostScreen(
                                                  initialPost: post,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  if (post.userId == currentUser.id ||
                                      currentUser.role == UserRole.Admin ||
                                      currentUser.role == UserRole.SuperAdmin)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _confirmDelete(context, post),
                                    ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person,
                                  color: Colors.orangeAccent,
                                  size: 14,
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
                                      color: Colors.orangeAccent,
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Mini antena con promedio
                                Icon(
                                  Icons.settings_input_antenna,
                                  color: post.ratingAverage > 0
                                      ? Colors.orangeAccent
                                      : Colors.white24,
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  post.ratingAverage > 0
                                      ? post.ratingAverage.toStringAsFixed(1)
                                      : '—',
                                  style: TextStyle(
                                    color: post.ratingAverage > 0
                                        ? Colors.orangeAccent
                                        : Colors.white38,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (post.locationName.isNotEmpty) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.redAccent,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      post.locationName,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
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
                              const SizedBox(height: 8),
                            ],
                            if (post.description.isNotEmpty)
                              Text(
                                post.description,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
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
          child: CircularProgressIndicator(color: Colors.orangeAccent),
        ),
        error: (err, _) => Center(
          child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
        ),
      ),
    ),
  ],
),
),
);
}

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: 'Inter',
          ),
          cursorColor: Colors.orangeAccent,
          decoration: InputDecoration(
            hintText: 'BUSCAR PICÁ...',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 12,
              fontFamily: 'Courier',
              letterSpacing: 1.5,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: Colors.orangeAccent.withValues(alpha: 0.5),
              size: 20,
            ),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white38,
                      size: 18,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (val) {
            setState(() => _searchQuery = val);
          },
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, FoodPost post) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '¿Eliminar picá?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Esta acción no se puede deshacer, pibe. ¿Estás seguro?',
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
                    .read(foodProvider.notifier)
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

  void _showPostDetails(BuildContext context, dynamic post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.imageUrls.isNotEmpty)
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            post.imageUrls[i],
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              // Reproductor de video (si tiene)
              if (post.videoUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                VideoSection(
                  videoUrls: post.videoUrls,
                  storagePath: 'food_media',
                  accentColor: Colors.orangeAccent,
                ),
              ],
              const SizedBox(height: 20),
              Text(
                post.locationName.isNotEmpty ? post.locationName : post.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Por ${post.authorName} • ${DateFormat('dd/MM HH:mm').format(post.createdAt)}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 16),
              Text(
                post.description,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              // Rating tipo antena
              AntennaRating(
                postId: post.id,
                collectionName: 'food_tracker',
                accentColor: Colors.orangeAccent,
                currentAverage: post.ratingAverage,
                ratingCount: post.ratingCount,
              ),
              // Sección de comentarios
              CommentsSection(
                postId: post.id,
                collectionName: 'food_tracker',
                postOwnerId: post.userId,
                postTitle: post.locationName.isNotEmpty
                    ? post.locationName
                    : post.title,
                postRouteName: FoodScreen.routeName,
                accentColor: Colors.orangeAccent,
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}
