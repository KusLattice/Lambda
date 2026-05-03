import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/providers/market_provider.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/screens/create_market_item_screen.dart';
import 'package:lambda_app/models/market_model.dart';
import 'package:lambda_app/widgets/comments_section.dart';
import 'package:lambda_app/widgets/video_section.dart';
import 'package:lambda_app/widgets/image_zoom_gallery.dart';

class MercadoNegroScreen extends ConsumerStatefulWidget {
  static const String routeName = '/mercado-negro';
  const MercadoNegroScreen({super.key});

  @override
  ConsumerState<MercadoNegroScreen> createState() => _MercadoNegroScreenState();
}

class _MercadoNegroScreenState extends ConsumerState<MercadoNegroScreen> {
  String _selectedCategory = 'Todo';
  bool _hasOpenedInitialItem = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
  final List<String> _categories = [
    'Todo',
    'Herramientas',
    'Vehículos',
    'Servicios',
    'Varios',
  ];

  @override
  Widget build(BuildContext context) {
    final marketAsync = ref.watch(marketItemsProvider);
    final initialItemId = ModalRoute.of(context)!.settings.arguments as String?;
    final currentUser = ref.watch(authProvider).valueOrNull;
    final isGuest = currentUser?.role == UserRole.TecnicoInvitado;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'MERCADO NEGRO',
          style: TextStyle(
            color: Colors.greenAccent,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.grey[900],
        iconTheme: const IconThemeData(color: Colors.greenAccent),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildCategoryFilter(),
          Expanded(
            child: marketAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text(
                  'Error: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              data: (items) {
                final filteredItems = items.where((item) {
                  final matchesCategory = _selectedCategory == 'Todo' ||
                      item.category.displayName == _selectedCategory;
                  final matchesSearch = _searchQuery.isEmpty ||
                      item.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      item.description.toLowerCase().contains(_searchQuery.toLowerCase());
                  return matchesCategory && matchesSearch;
                }).toList();

                if (filteredItems.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay publicaciones en esta categoría.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];

                    // Deep Link
                    if (initialItemId != null &&
                        !_hasOpenedInitialItem &&
                        item.id == initialItemId) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_hasOpenedInitialItem) {
                          setState(() => _hasOpenedInitialItem = true);
                          _showItemDetails(context, item);
                        }
                      });
                    }

                    return _buildMarketCard(item);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton(
              onPressed: () {
                Navigator.pushNamed(context, '/create-market-item');
              },
              backgroundColor: Colors.greenAccent,
              child: const Icon(Icons.add, color: Colors.black, size: 28),
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
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (val) => setState(() => _searchQuery = val),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: Colors.greenAccent,
          decoration: InputDecoration(
            hintText: 'Buscar en Mercado Negro...',
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: Colors.greenAccent,
              size: 18,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white.withOpacity(0.5),
                      size: 16,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          ),
          textAlignVertical: TextAlignVertical.center,
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = category == _selectedCategory;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                category,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: Colors.greenAccent,
              backgroundColor: Colors.grey[850],
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedCategory = category);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarketCard(MarketItem item) {
    final hasPrice = item.price != null;
    final displayDate =
        '${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}';
    final imageUrl = item.imageUrls.isNotEmpty ? item.imageUrls.first : '';

    return InkWell(
      onTap: () => _showItemDetails(context, item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen superior (aspect ratio cuadrado o ligeramente apaisado)
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.isNotEmpty)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[800],
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.image_not_supported,
                        color: Colors.white54,
                      ),
                    ),
                  // Gradiente inferior para destacar texto si lo hubiera (opcional)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.8),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Badge de precio
                  if (hasPrice)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '\$${item.price}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  // Botones de acción (Edit/Delete)
                  Positioned(top: 8, left: 8, child: _buildActionButtons(item)),
                ],
              ),
            ),
            // Detalles inferiores
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(
                              Icons.person,
                              color: Colors.greenAccent,
                              size: 10,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.sellerName,
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayDate,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemDetails(BuildContext context, MarketItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageUrls.isNotEmpty)
                SizedBox(
                  height: 300,
                  child: Stack(
                    children: [
                      PageView.builder(
                        itemCount: item.imageUrls.length,
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ImageZoomGallery(
                                    imageUrls: item.imageUrls,
                                    initialIndex: index,
                                  ),
                                ),
                              );
                            },
                            child: Hero(
                              tag: 'market_${item.id}_$index',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  item.imageUrls[index],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (item.imageUrls.length > 1)
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
                              '1/${item.imageUrls.length}',
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
              if (item.videoUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                VideoSection(
                  videoUrls: item.videoUrls,
                  storagePath: 'market_media',
                  accentColor: Colors.greenAccent,
                ),
              ],
              const SizedBox(height: 24),
              Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person, color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Vendido por: ${item.sellerName}',
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
                  const Spacer(),
                  if (item.price != null)
                    Text(
                      '\$${item.price}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white12),
              const SizedBox(height: 24),
              const Text(
                'DESCRIPCIÓN',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              // Comentarios del producto
              CommentsSection(
                postId: item.id,
                collectionName: 'market_items',
                postOwnerId: item.authorId,
                postTitle: item.title,
                postRouteName: MercadoNegroScreen.routeName,
                accentColor: Colors.greenAccent,
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(MarketItem item) {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final isOwner = item.authorId == user.id;
    final isSuperAdmin = user.role == UserRole.SuperAdmin;
    final isAdmin = user.role == UserRole.SuperAdmin;

    if (!isOwner && !isAdmin) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isOwner || isSuperAdmin)
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CreateMarketItemScreen(initialItem: item),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.edit, color: Colors.blueAccent, size: 16),
            ),
          ),
        if (isOwner || isSuperAdmin) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _confirmDeleteMarket(context, item),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.delete,
                color: Colors.redAccent,
                size: 16,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _confirmDeleteMarket(BuildContext context, MarketItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          '¿Eliminar publicación?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '¿Estás seguro de que quieres borrar esto del Mercado Negro?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(marketNotifierProvider.notifier)
                    .deleteMarketItem(
                      item.id,
                      imageUrls: item.imageUrls,
                      videoUrls: item.videoUrls,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Eliminado correctamente.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
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
}
