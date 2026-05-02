import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/providers/semantic_search_provider.dart';
import 'package:lambda_app/providers/theme_provider.dart';
import 'package:lambda_app/widgets/grid_background.dart';

class SemanticSearchScreen extends ConsumerStatefulWidget {
  static const String routeName = '/semantic-search';
  const SemanticSearchScreen({super.key});

  @override
  ConsumerState<SemanticSearchScreen> createState() =>
      _SemanticSearchScreenState();
}

class _SemanticSearchScreenState extends ConsumerState<SemanticSearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(semanticSearchProvider);
    final initialQuery = ModalRoute.of(context)!.settings.arguments as String?;
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        children: [
          const GridBackground(child: SizedBox.expand()),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.arrow_back_ios,
                          color: theme.accent,
                          size: 20,
                        ),
                      ),
                      Text(
                        'BÚSQUEDA DEL SISTEMA',
                        style: TextStyle(
                          color: theme.accent,
                          fontFamily: 'Courier',
                          letterSpacing: 2,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.radar,
                        color: theme.accent,
                        size: 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Barra de búsqueda minimalista
                  Container(
                    decoration: BoxDecoration(
                      color: theme.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.accent.withValues(alpha: 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.accent.withValues(alpha: 0.1),
                          blurRadius: 10,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl
                        ..text = (_searchCtrl.text.isEmpty
                            ? (initialQuery ?? '')
                            : _searchCtrl.text),
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 16,
                        fontFamily: 'Courier',
                      ),
                      cursorColor: theme.accent,
                        decoration: InputDecoration(
                          hintText: 'ESCRIBE AQUÍ...',
                          hintStyle: TextStyle(
                            color: theme.onSurface.withValues(alpha: 0.4),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: theme.accent,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      color: Colors.white38, size: 16),
                                  onPressed: () {
                                    setState(() {
                                      _searchCtrl.clear();
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onChanged: (val) => setState(() {}),
                      onSubmitted: (val) =>
                          ref.read(semanticSearchProvider.notifier).search(val),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Resultados
                  Expanded(
                    child: resultsAsync.when(
                      data: (results) => results.isEmpty
                          ? const Center(
                              child: Text(
                                'Sin señales detectadas.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (context, index) {
                                final result = results[index];
                                return _SemanticResultCard(result: result);
                              },
                            ),
                      loading: () => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: theme.accent,
                              strokeWidth: 2,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Sincronizando con Gemini...',
                              style: TextStyle(
                                color: theme.accent,
                                fontFamily: 'Courier',
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      error: (e, _) => Center(
                        child: Text(
                          'Error: $e',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SemanticResultCard extends ConsumerWidget {
  final SemanticResult result;
  const _SemanticResultCard({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return InkWell(
      onTap: () {
        String route = '';
        dynamic args;

        switch (result.source) {
          case 'hospedaje':
            route = '/hospedaje';
            args = result.id; // Pasamos el ID para que la pantalla lo abra
            break;
          case 'picás':
            route = '/food';
            args = result.id;
            break;
          case 'mercado':
            route = '/mercado-negro';
            args = result.id;
            break;
          case 'chambas':
            route = '/chambas';
            args = result.id;
            break;
          case 'tips_hacks':
            route = '/tips-hacks';
            args = result.id;
            break;
          case 'la_nave':
            route = '/la_nave';
            args = result.id;
            break;
          case 'random':
            route = '/random';
            args = result.id;
            break;
          case 'mensajes':
            // Auditoría: no hay ruta directa por ahora, pero podríamos mostrar un diálogo
            // o simplemente no hacer nada si es solo visualización.
            break;
        }

        if (route.isNotEmpty) {
          Navigator.pushNamed(context, route, arguments: args);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.accent.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: theme.accent.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildSourceBadge(result.source, theme.accent),
                if (result.distance != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${result.distance!.toStringAsFixed(1)} KM',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${(result.score * 100).toStringAsFixed(0)}% COINCIDENCIA',
                  style: const TextStyle(color: Colors.grey, fontSize: 9),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.title,
                    style: TextStyle(
                      color: result.source == 'mensajes'
                          ? Colors.orangeAccent
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (result.coordinates != null)
                  IconButton(
                    icon: const Icon(Icons.map_outlined, color: Colors.amber, size: 18),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/map',
                        arguments: result.coordinates,
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              result.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceBadge(String source, Color accent) {
    String label = source.toUpperCase();
    Color color = accent.withValues(alpha: 0.8);
    IconData icon = Icons.info_outline;

    switch (source) {
      case 'hospedaje':
        icon = Icons.hotel;
        break;
      case 'picás':
        icon = Icons.restaurant;
        break;
      case 'mercado':
        icon = Icons.shopping_basket;
        break;
      case 'chambas':
        icon = Icons.work;
        break;
      case 'la_nave':
        icon = Icons.forum;
        break;
      case 'mensajes':
        icon = Icons.chat_bubble;
        color = Colors.orangeAccent;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
