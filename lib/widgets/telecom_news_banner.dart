import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lambda_app/services/rss_news_service.dart';
import 'package:lambda_app/providers/theme_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

const Map<String, Color> _categoryColors = {
  'chile': Color(0xFFFF4B4B),
  'global': Color(0xFF4D9FFF),
  'tecnica': Color(0xFF00FF9C),
  'huawei': Color(0xFFFF8C00),
  'comercial': Color(0xFFA855F7),
};

const Map<String, String> _categoryLabels = {
  'chile': '🇨🇱 CHILE',
  'global': '🌐 GLOBAL',
  'tecnica': '🔧 TÉCNICA',
  'huawei': '📡 HUAWEI',
  'comercial': '💼 MERCADO',
};

final _rssService = RssNewsService();

class TelecomNewsBanner extends ConsumerStatefulWidget {
  const TelecomNewsBanner({super.key});

  @override
  ConsumerState<TelecomNewsBanner> createState() => _TelecomNewsBannerState();
}

class _TelecomNewsBannerState extends ConsumerState<TelecomNewsBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  Timer? _autoTimer;
  int _currentPage = 0;
  List<TelecomNewsItem> _news = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    _sub = _rssService.newsStream().listen((items) {
      if (mounted) {
        setState(() => _news = items);
        _startAutoScroll();
      }
    });
  }

  void _startAutoScroll() {
    _autoTimer?.cancel();
    if (_news.isEmpty) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _news.isEmpty) return;
      setState(() {
        _currentPage = (_currentPage + 1) % _news.length;
      });
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _fadeCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _launchUrl(String urlString) async {
    if (urlString.isEmpty) return;
    final uri = Uri.parse(urlString);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('No se pudo abrir $urlString');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final accent = theme.accent;

    if (_news.isEmpty) {
      return Container(
        height: 110,
        width: double.infinity,
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(
          child: Text(
            'CARGANDO DATA STREAM...',
            style: TextStyle(
              color: Colors.pink, // PRUEBA DE HOT RELOAD
              fontFamily: 'Courier',
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _launchUrl(_news[_currentPage].url),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          border: Border(
            bottom: BorderSide(color: accent.withValues(alpha: 0.15)),
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: _buildLinearContent(_news[_currentPage], theme, key: ValueKey(_currentPage)),
        ),
      ),
    );
  }

  Widget _buildLinearContent(TelecomNewsItem item, LambdaTheme theme, {Key? key}) {
    final accent = theme.accent;
    final catColor = _categoryColors[item.category] ?? Colors.white24;

    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Previsualización de Imagen
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 140,
              height: 140,
              color: Colors.white.withValues(alpha: 0.05),
              child: item.imageUrl != null
                  ? Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint('ERROR: Falló carga de imagen para "${item.title}": ${item.imageUrl}');
                        return _buildCategoryFallback(item.category);
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(child: CircularProgressIndicator(strokeWidth: 2, color: accent.withValues(alpha: 0.2)));
                      },
                    )
                  : _buildCategoryFallback(item.category),
            ),
          ),
          const SizedBox(width: 14),
          // Contenido de Texto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Título en 2 líneas
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    letterSpacing: 0.1,
                  ),
                ),
                const Spacer(),
                // Metadatos
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.1),
                        border: Border.all(color: catColor.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _categoryLabels[item.category] ?? 'INFO',
                        style: TextStyle(
                          color: catColor,
                          fontSize: 8,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.source.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 9,
                        fontFamily: 'Inter',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFallback(String category) {
    IconData icon;
    switch (category) {
      case 'chile': icon = Icons.map; break;
      case 'global': icon = Icons.public; break;
      case 'tecnica': icon = Icons.settings_input_component; break;
      case 'huawei': icon = Icons.router; break;
      case 'comercial': icon = Icons.business; break;
      default: icon = Icons.newspaper;
    }
    return Center(child: Icon(icon, color: Colors.white10, size: 30));
  }
}
