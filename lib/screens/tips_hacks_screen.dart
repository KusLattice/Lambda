import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/hack_provider.dart';
import 'package:lambda_app/screens/create_hack_screen.dart';
import 'package:lambda_app/models/secret_hack_model.dart';
import 'package:lambda_app/widgets/video_section.dart';
import 'package:lambda_app/widgets/image_zoom_gallery.dart';

class TipsHacksScreen extends ConsumerStatefulWidget {
  static const String routeName = '/tips_hacks';
  const TipsHacksScreen({super.key});

  @override
  ConsumerState<TipsHacksScreen> createState() => _TipsHacksScreenState();
}

class _TipsHacksScreenState extends ConsumerState<TipsHacksScreen> {
  bool _hasOpenedInitialHack = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.valueOrNull;
    final hacksAsync = ref.watch(hacksProvider);
    final initialHackId = ModalRoute.of(context)!.settings.arguments as String?;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text(
            'LA LIBRETITA',
            style: TextStyle(
              color: Colors.greenAccent,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.grey[900],
          iconTheme: const IconThemeData(color: Colors.greenAccent),
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.greenAccent,
            labelColor: Colors.greenAccent,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.help_outline), text: 'Preguntas'),
              Tab(icon: Icon(Icons.lightbulb_outline), text: 'Datitos'),
              Tab(icon: Icon(Icons.vpn_key), text: 'Claves'),
            ],
          ),
        ),
        body: hacksAsync.when(
          data: (hacks) {
            final preguntas = hacks
                .where((h) => h.category == 'Preguntas')
                .toList();
            final datitos = hacks
                .where((h) => h.category == 'Datitos')
                .toList();
            final claves = hacks.where((h) => h.category == 'Claves').toList();

            // Deep Link Logic
            if (initialHackId != null && !_hasOpenedInitialHack) {
              final hackToOpen = hacks
                  .where((h) => h.id == initialHackId)
                  .firstOrNull;
              if (hackToOpen != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_hasOpenedInitialHack) {
                    setState(() => _hasOpenedInitialHack = true);

                    // Cambiar de tab automáticamente
                    int tabIndex = 0;
                    if (hackToOpen.category == 'Datitos') tabIndex = 1;
                    if (hackToOpen.category == 'Claves') tabIndex = 2;

                    DefaultTabController.of(context).animateTo(tabIndex);
                    _showHackDetails(context, hackToOpen, user);
                  }
                });
              }
            }

            return TabBarView(
              children: [
                _buildHackList(preguntas, user, context),
                _buildHackList(datitos, user, context),
                _buildHackList(claves, user, context),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.greenAccent),
          ),
          error: (err, _) => Center(
            child: Text(
              'Error al desencriptar: $err',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
        floatingActionButton: user?.canAccessVaultMartian == true
            ? FloatingActionButton(
                backgroundColor: Colors.greenAccent,
                child: const Icon(Icons.add, color: Colors.black),
                onPressed: () =>
                    Navigator.pushNamed(context, CreateHackScreen.routeName),
              )
            : null,
      ),
    );
  }

  Widget _buildHackList(
    List<SecretHack> hacks,
    User? user,
    BuildContext context,
  ) {
    if (hacks.isEmpty) {
      return const Center(
        child: Text(
          'Aún no hay apuntes en esta sección.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      itemCount: hacks.length,
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, index) {
        final hack = hacks[index];
        return InkWell(
          onTap: () => _showHackDetails(context, hack, user),
          child: Card(
            color: Colors.grey[900],
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: Colors.greenAccent.withValues(alpha: 0.5),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              _getIconForCategory(hack.category),
                              color: Colors.greenAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hack.title.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (user != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hack.userId == user.id ||
                                user.role == UserRole.SuperAdmin)
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
                                          CreateHackScreen(initialHack: hack),
                                    ),
                                  );
                                },
                              ),
                            if (hack.userId == user.id ||
                                user.isAdmin)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    _confirmDelete(context, hack, user),
                              ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      hack.info,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'Courier',
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (hack.imageUrls.isNotEmpty ||
                      hack.videoUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (hack.imageUrls.isNotEmpty)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  hack.imageUrls.first,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              if (hack.imageUrls.length > 1)
                                Positioned(
                                  bottom: 2,
                                  right: 2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+${hack.imageUrls.length - 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        if (hack.imageUrls.isNotEmpty &&
                            hack.videoUrls.isNotEmpty)
                          const SizedBox(width: 8),
                        if (hack.videoUrls.isNotEmpty)
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.greenAccent.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.play_circle_outline,
                              color: Colors.greenAccent,
                              size: 30,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (hack.location != null && hack.location!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.orangeAccent,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            hack.location!,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                              fontFamily: 'Courier',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Aportado por: ${hack.authorName}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showHackDetails(BuildContext context, SecretHack hack, User? user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Colors.greenAccent, width: 0.5),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getIconForCategory(hack.category),
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    hack.category.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (hack.imageUrls.isNotEmpty)
                SizedBox(
                  height: 250,
                  child: PageView.builder(
                    itemCount: hack.imageUrls.length,
                    itemBuilder: (context, i) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ImageZoomGallery(
                                imageUrls: hack.imageUrls,
                                initialIndex: i,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              hack.imageUrls[i],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (hack.videoUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                VideoSection(
                  videoUrls: hack.videoUrls,
                  storagePath: 'hacks_media',
                  accentColor: Colors.greenAccent,
                ),
              ],
              const SizedBox(height: 24),
              Text(
                hack.title.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Courier',
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  hack.info,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'Courier',
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ),
              if (hack.location != null && hack.location!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.orangeAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hack.location!,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              const Divider(color: Colors.white12),
              const SizedBox(height: 16),
              Text(
                'Aportado por: ${hack.authorName}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, SecretHack hack, User user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '¿Eliminar dato secreto?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '¿Estás seguro de que quieres borrar este dato del vault?',
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
                    .read(hacksProvider.notifier)
                    .deleteHack(
                      hack.id,
                      user,
                      imageUrls: hack.imageUrls,
                      videoUrls: hack.videoUrls,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dato secreto eliminado.')),
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

  IconData _getIconForCategory(String category) {
    switch (category) {
      case 'Preguntas':
        return Icons.help_outline;
      case 'Claves':
        return Icons.vpn_key;
      case 'Datitos':
      default:
        return Icons.lightbulb_outline;
    }
  }
}
