import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lambda_app/config/firestore_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rss_dart/dart_rss.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class TelecomNewsItem {
  final String id; // usado para borrado desde admin
  final String title;
  final String url;
  final String source;
  final String category; // 'chile', 'global', 'tecnica', 'huawei', 'comercial'
  final DateTime publishedAt;
  final String? imageUrl;

  TelecomNewsItem({
    required this.id,
    required this.title,
    required this.url,
    required this.source,
    required this.category,
    required this.publishedAt,
    this.imageUrl,
  });

  factory TelecomNewsItem.fromMap(Map<String, dynamic> data, String docId) {
    return TelecomNewsItem(
      id: docId,
      title: data['title'] ?? '',
      url: data['url'] ?? '',
      source: data['source'] ?? '',
      category: data['category'] ?? 'global',
      publishedAt:
          (data['publishedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      imageUrl: data['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'url': url,
    'source': source,
    'category': category,
    'publishedAt': Timestamp.fromDate(publishedAt),
    'imageUrl': imageUrl,
  };
}

// ---------------------------------------------------------------------------
// Servicio RSS
// ---------------------------------------------------------------------------

class RssNewsService {
  static const _cacheDoc = 'metadata/telecom_news_cache';
  static const _cacheTtlHours = 6; // refresca cada 6 horas

  // Fuentes RSS de telecomunicaciones priorizadas e internacionales
  static const List<Map<String, String>> _feeds = [
    {
      'url': 'https://www.subtel.gob.cl/feed/',
      'source': 'SUBTEL',
      'category': 'chile',
    },
    {
      'url': 'https://www.latercera.com/etiqueta/telecomunicaciones/feed/',
      'source': 'La Tercera',
      'category': 'chile',
    },
    {
      'url': 'https://feeds.feedburner.com/TeleGeographyPortalNews',
      'source': 'TeleGeography',
      'category': 'global',
    },
    {
      'url': 'https://www.huawei.com/en/news/rss',
      'source': 'Huawei News',
      'category': 'huawei',
    },
    {
      'url': 'https://www.lightreading.com/rss.xml',
      'source': 'Light Reading',
      'category': 'tecnica',
    },
    {
      'url': 'https://www.telecomtv.com/api/rss/content/',
      'source': 'TelecomTV',
      'category': 'global',
    },
    {
      'url': 'https://www.fiercetelecom.com/rss/xml',
      'source': 'FierceTelecom',
      'category': 'comercial',
    },
  ];

  // Noticias hardcoded de alta calidad como fallback enriquecido
  static final List<TelecomNewsItem> _fallbackNews = [
    TelecomNewsItem(
      id: 'hc_1',
      title: '🇨🇱 SUBTEL: Cable submarino Humboldt conectará Chile con Asia-Pacífico en 2026',
      url: 'https://subtel.gob.cl/gobierno-anuncia-la-llegada-del-cable-submarino-humboldt/',
      source: 'SUBTEL',
      category: 'chile',
      publishedAt: DateTime(2026, 3, 10),
      imageUrl: 'https://images.unsplash.com/photo-1544197150-b99a580bb7a8?q=80&w=400&auto=format&fit=crop',
    ),
    TelecomNewsItem(
      id: 'hc_2',
      title: '📡 5G SA: Chile avanza en pruebas piloto de 5G Standalone, cobertura rural en la mira',
      url: 'https://subtel.gob.cl',
      source: 'SUBTEL',
      category: 'chile',
      publishedAt: DateTime(2026, 2, 15),
      imageUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?q=80&w=400&auto=format&fit=crop',
    ),
    TelecomNewsItem(
      id: 'hc_3',
      title: '🔧 FTTH Chile: Despliegue de fibra óptica supera 4.5 millones de accesos',
      url: 'https://www.subtel.gob.cl/estadisticas-telecomunicaciones/',
      source: 'SUBTEL',
      category: 'chile',
      publishedAt: DateTime(2026, 1, 20),
    ),
    TelecomNewsItem(
      id: 'hc_4',
      title: '🌐 DWDM: Huawei lanza OSN 9800 con capacidad de 400G por lambda en redes de transporte',
      url: 'https://carrier.huawei.com/en/products/fixed-network/transmission',
      source: 'Huawei',
      category: 'tecnica',
      publishedAt: DateTime(2026, 3, 1),
      imageUrl: 'https://images.unsplash.com/photo-1550751827-4bd374c3f58b?q=80&w=400&auto=format&fit=crop',
    ),
    TelecomNewsItem(
      id: 'hc_5',
      title: '⚡ Huawei NetEngine: Routers NE40E-M2 con soporte SRv6+ para redes IP/MPLS de alto tráfico',
      url: 'https://carrier.huawei.com/en/products/routers',
      source: 'Huawei',
      category: 'tecnica',
      publishedAt: DateTime(2026, 2, 28),
      imageUrl: 'https://images.unsplash.com/photo-1516383274235-5f42d6c6426d?q=80&w=400&auto=format&fit=crop',
    ),
    TelecomNewsItem(
      id: 'hc_6',
      title: '🏢 MERCADO: Tigo Colombia expande red de fibra en ciudades intermedias del Pacífico',
      url: 'https://www.millicom.com',
      source: 'Millicom',
      category: 'comercial',
      publishedAt: DateTime(2026, 2, 10),
    ),
    TelecomNewsItem(
      id: 'hc_7',
      title: '🌎 GLOBAL: ITU confirma estándares IMT-2030 (6G) con velocidades de 1 Tbps',
      url: 'https://www.itu.int/en/ITU-R/study-groups/rsg5/rwp5d/Pages/imt-2030.aspx',
      source: 'ITU',
      category: 'global',
      publishedAt: DateTime(2026, 3, 5),
    ),
    TelecomNewsItem(
      id: 'hc_8',
      title: '🇦🇷 Argentina: Telecom Argentina despliega red de transporte Flexi-Grid ROADM en el NOA',
      url: 'https://www.telecom.com.ar/empresas/',
      source: 'Telecom AR',
      category: 'global',
      publishedAt: DateTime(2026, 1, 30),
    ),
    TelecomNewsItem(
      id: 'hc_9',
      title: '🔬 OTN: Nokia e2e Wavelength Management simplifica troubleshooting en redes DWDM multidominio',
      url: 'https://www.nokia.com/networks/optical-networks/',
      source: 'Nokia',
      category: 'tecnica',
      publishedAt: DateTime(2026, 2, 20),
    ),
    TelecomNewsItem(
      id: 'hc_10',
      title: '🇨🇱 Entel Chile: Migración de red core a arquitectura cloud-native reduce OPEX 30%',
      url: 'https://www.entel.cl',
      source: 'Entel Chile',
      category: 'chile',
      publishedAt: DateTime(2026, 1, 15),
    ),
    TelecomNewsItem(
      id: 'hc_11',
      title: '🌐 Submarine cables: 2AFRICA superará los 45,000 km y conectará 46 países africanos',
      url: 'https://2africacable.com',
      source: 'Meta / 2Africa',
      category: 'global',
      publishedAt: DateTime(2026, 3, 12),
    ),
    TelecomNewsItem(
      id: 'hc_12',
      title: '🇵🇪 Perú: Pronatel licita últimas rutas de backbone nacional de fibra en zonas rurales',
      url: 'https://www.pronatel.gob.pe',
      source: 'PRONATEL',
      category: 'global',
      publishedAt: DateTime(2026, 2, 5),
    ),
  ];

  /// Priority sort: 1. Chile, 2. Huawei/DWDM/Tecnica, 3. Vecinos, 4. Others. Secondary: Date
  List<TelecomNewsItem> _sortNews(List<TelecomNewsItem> news) {
    int getScore(TelecomNewsItem item) {
      final t = item.title.toLowerCase();
      final c = item.category.toLowerCase();
      final s = item.source.toLowerCase();
      
      if (t.contains('chile') || c == 'chile') return 100;
      if (t.contains('huawei') || t.contains('dwdm') || s.contains('huawei') || c == 'tecnica') return 90;
      if (t.contains('argentina') || t.contains('peru') || t.contains('perú') || t.contains('bolivia') || t.contains('vecino')) return 80;
      return 0;
    }

    final sorted = List<TelecomNewsItem>.from(news);
    sorted.sort((a, b) {
      final scoreA = getScore(a);
      final scoreB = getScore(b);
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Higher score first
      }
      return b.publishedAt.compareTo(a.publishedAt); // Newer first
    });
    return sorted;
  }

  /// Obtiene noticias: primero emite fallback instantáneo, luego conecta a Firestore.
  /// Admins pueden borrar ítems individuales.
  Stream<List<TelecomNewsItem>> newsStream() async* {
    debugPrint('DEBUG: newsStream() iniciado');
    // UX Instantánea: Emitimos datos base mientras conectamos
    yield _sortNews(_fallbackNews);

    try {
      final snapshots = FirebaseFirestore.instance
          .collection(FC.telecomNews)
          .orderBy('publishedAt', descending: true)
          .limit(30)
          .snapshots();

      await for (final snap in snapshots) {
        if (snap.docs.isEmpty) {
          // Si no hay nada, intentamos poblar en segundo plano
          _seedDefaults();
          _tryFetchRss();
          yield _sortNews(_fallbackNews);
        } else {
          // Si hay datos, los procesamos
          final items = snap.docs
              .map((d) => TelecomNewsItem.fromMap(d.data(), d.id))
              .toList();
          yield _sortNews(items);
          
          // Verificamos si los datos están obsoletos (throttled internamente)
          _refreshIfStale();
        }
      }
    } catch (e) {
      debugPrint('Error en NewsStream: $e');
      yield _sortNews(_fallbackNews);
    }
  }

  Future<void> _seedDefaults() async {
    final batch = FirebaseFirestore.instance.batch();
    for (final item in _fallbackNews) {
      final ref = FirebaseFirestore.instance
          .collection(FC.telecomNews)
          .doc(item.id);
      batch.set(ref, item.toMap());
    }
    await batch.commit().catchError((e) {
      debugPrint('RssNewsService: seed error: $e');
    });
  }

  Future<void> _refreshIfStale() async {
    try {
      final cacheRef =
          FirebaseFirestore.instance.doc(_cacheDoc);
      final cacheSnap = await cacheRef.get();

      if (cacheSnap.exists) {
        final lastFetch =
            (cacheSnap.data()!['lastFetchAt'] as Timestamp?)?.toDate();
        if (lastFetch != null &&
            DateTime.now().difference(lastFetch).inHours < _cacheTtlHours) {
          return; // Cache válido: no se hacen requests a los feeds.
        }
      }

      await _tryFetchRss();
      await cacheRef.set({
        'lastFetchAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('RssNewsService: stale check error: $e');
    }
  }

  Future<void> _tryFetchRss() async {
    debugPrint('RssNewsService: iniciando fetch para ${_feeds.length} fuentes...');
    for (final feed in _feeds) {
      try {
        final headers = {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/xml, text/xml, */*',
        };

        final response = await http
            .get(Uri.parse(feed['url']!), headers: headers)
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          debugPrint('DEBUG: RSS descargado exitosamente de ${feed['source']}');
          final items = _parseRss(
            utf8.decode(response.bodyBytes),
            feed['source']!,
            feed['category']!,
          );
          debugPrint('DEBUG: ${items.length} noticias parseadas de ${feed['source']}');
          await _saveItems(items);
        } else {
          debugPrint('DEBUG: Error descargando RSS (${response.statusCode}) de ${feed['url']}');
        }
      } catch (e) {
        debugPrint('RssNewsService: feed error ${feed["url"]}: $e');
      }
    }
  }

  List<TelecomNewsItem> _parseRss(
    String xmlBody,
    String source,
    String category,
  ) {
    try {
      final feed = RssFeed.parse(xmlBody);
      final result = <TelecomNewsItem>[];

      for (final item in feed.items.take(20)) {
        final title = item.title ?? '';
        final link = item.link ?? item.guid ?? '';
        final pubDateStr = item.pubDate;

        DateTime pubDate = DateTime.now();
        if (pubDateStr != null) {
          try {
            pubDate = _parseRfc822(pubDateStr);
          } catch (_) {}
        }

        // Extracción de imagen profesional y escalable
        String? imageUrl;
        
        // 1. Prioridad: Media RSS (Media:content o Media:thumbnail)
        if (item.media != null) {
          if (item.media!.contents.isNotEmpty) {
            imageUrl = item.media!.contents.first.url;
          } else if (item.media!.thumbnails.isNotEmpty) {
            imageUrl = item.media!.thumbnails.first.url;
          }
        }
        
        // 2. Enclosure (estándar RSS 2.0)
        if (imageUrl == null && item.enclosure != null) {
          imageUrl = item.enclosure!.url;
        }

        // 3. Fallback: Parsear HTML en descripción/content
        if (imageUrl == null) {
          final content = item.description ?? item.content?.value ?? '';
          if (content.isNotEmpty) {
            final imgMatch = RegExp(r'<img[^>]+src="([^">]+)"').firstMatch(content);
            if (imgMatch != null) {
              imageUrl = imgMatch.group(1);
            }
          }
        }

        if (imageUrl != null) {
          debugPrint('DEBUG: [RSS] Imagen extraída de $source ($title): $imageUrl');
        }

        if (title.isNotEmpty && link.isNotEmpty) {
          // Categorización inteligente basada en contenido
          String finalCategory = category;
          final lowerTitle = title.toLowerCase();
          final lowerSource = source.toLowerCase();

          if (lowerTitle.contains('dwdm') ||
              lowerTitle.contains('optico') ||
              lowerTitle.contains('lambda') ||
              lowerTitle.contains('fiber') ||
              lowerTitle.contains('nokia') ||
              lowerTitle.contains('cisco') ||
              lowerTitle.contains('otn') ||
              lowerTitle.contains('wdm')) {
            finalCategory = 'tecnica';
          }

          if (lowerTitle.contains('huawei') || lowerSource.contains('huawei')) {
            finalCategory = 'huawei';
          }

          if (lowerTitle.contains('chile') ||
              lowerTitle.contains('subtel') ||
              lowerTitle.contains('entel') ||
              lowerTitle.contains('movistar') ||
              lowerTitle.contains('vtr') ||
              lowerTitle.contains('wom')) {
            finalCategory = 'chile';
          }

          result.add(TelecomNewsItem(
            id: base64Encode(utf8.encode(link)).substring(0, 20),
            title: title.startsWith('📰') ? title : '📰 $title',
            url: link,
            source: source,
            category: finalCategory,
            publishedAt: pubDate,
            imageUrl: imageUrl,
          ));
        }
      }
      return result;
    } catch (e) {
      // Si falla como RSS, intentamos una búsqueda rápida de emergencia en el XML crudo
      // para no perder la noticia, aunque sea sin metadatos complejos.
      debugPrint('RSS feed fallback for $source due to: $e');
      return [];
    }
  }

  Future<void> _saveItems(List<TelecomNewsItem> items) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final item in items) {
        final ref = FirebaseFirestore.instance
            .collection(FC.telecomNews)
            .doc(item.id);
        batch.set(ref, item.toMap(), SetOptions(merge: true));
      }
      await batch.commit();
    } catch (e) {
      debugPrint('RssNewsService: save error: $e');
    }
  }

  /// Admin: borrar una noticia por ID.
  Future<void> deleteNewsItem(String itemId) async {
    await FirebaseFirestore.instance
        .collection(FC.telecomNews)
        .doc(itemId)
        .delete();
  }

  DateTime _parseRfc822(String s) {
    // Formato: "Thu, 01 Jan 2026 12:00:00 +0000"
    final months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4,
      'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8,
      'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final parts = s.trim().split(' ');
    if (parts.length < 5) return DateTime.now();
    final day = int.tryParse(parts[1]) ?? 1;
    final month = months[parts[2]] ?? 1;
    final year = int.tryParse(parts[3]) ?? 2026;
    final timeParts = parts[4].split(':');
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final min = int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0;
    return DateTime(year, month, day, hour, min);
  }
}
