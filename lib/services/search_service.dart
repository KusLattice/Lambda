import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:lambda_app/config/app_config.dart';
import 'package:lambda_app/providers/semantic_search_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:lambda_app/models/lat_lng.dart' as local_coords;
import 'dart:math' as math;

class SearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final GenerativeModel _model;

  SearchService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: AppConfig.geminiApiKey,
    );
  }

  /// Realiza la búsqueda en toda la app y sus bases de datos.
  Future<List<SemanticResult>> performOmniSearch(
    String query, {
    bool isAdmin = false,
    local_coords.LatLng? userLocation,
  }) async {
    // 1. Analizar intención y extraer palabras clave normalizadas con Gemini
    final analysis = await _analyzeQueryWithGemini(query, isAdmin: isAdmin);
    final List<String> categories = analysis['categories'] ?? [];
    final List<String> keywords = analysis['keywords'] ?? [];
    final bool proximityIntent = analysis['proximityIntent']?.first == 'true';

    final List<Future<List<SemanticResult>>> searchTasks = [];

    // Protocolo de Inteligencia: Si hay categorías detectadas con alta confianza,
    // evitamos el "Search All" para no ensuciar con ruido irrelevante.
    bool hasStrongIntent = categories.isNotEmpty;
    bool searchAll = !hasStrongIntent;

    if (searchAll ||
        categories.contains('picás') ||
        categories.contains('comida')) {
      searchTasks.add(
        _searchCollection(
          'food_tracker', 
          'picás', 
          query, 
          keywords, 
          userLocation, 
          isIntentCategory: categories.contains('picás') || categories.contains('comida'),
          proximityIntent: proximityIntent,
        ),
      );
    }
    if (searchAll || categories.contains('hospedaje')) {
      searchTasks.add(
        _searchCollection(
          'lodging_tracker', 
          'hospedaje', 
          query, 
          keywords, 
          userLocation, 
          isIntentCategory: categories.contains('hospedaje'),
          proximityIntent: proximityIntent,
        ),
      );
    }
    if (searchAll || categories.contains('mercado')) {
      searchTasks.add(
        _searchCollection(
          'market_items', 
          'mercado', 
          query, 
          keywords, 
          userLocation, 
          isIntentCategory: categories.contains('mercado'),
          proximityIntent: proximityIntent,
        ),
      );
    }
    if (searchAll ||
        categories.contains('chambas') ||
        categories.contains('trabajo')) {
      searchTasks.add(
        _searchCollection(
          'chambas', 
          'chambas', 
          query, 
          keywords, 
          userLocation, 
          isIntentCategory: categories.contains('chambas') || categories.contains('trabajo'),
          proximityIntent: proximityIntent,
        ),
      );
    }
    if (searchAll || categories.contains('secret_vault')) {
      searchTasks.add(
        _searchCollection(
          'hacks_vault', 
          'tips_hacks', 
          query, 
          keywords, 
          userLocation, 
          isIntentCategory: categories.contains('secret_vault'),
          proximityIntent: proximityIntent,
        ),
      );
      searchTasks.add(
        _searchCollection(
          'nave_vault', 
          'la_nave', 
          query, 
          keywords, 
          userLocation, 
          isIntentCategory: categories.contains('secret_vault'),
          proximityIntent: proximityIntent,
        ),
      );
    }
    if (searchAll || categories.contains('random')) {
      searchTasks.add(
        _searchCollection(
          'random_board', 
          'random', 
          query, 
          keywords, 
          userLocation, 
          isIntentCategory: categories.contains('random'),
          proximityIntent: proximityIntent,
        ),
      );
    }

    // Búsqueda de Auditoría de Mensajes (Solo para Admins)
    if (isAdmin &&
        (searchAll ||
            categories.contains('mensajes') ||
            categories.contains('auditoria') ||
            categories.contains('historial'))) {
      searchTasks.add(_searchMessages(query, keywords));
    }

    final resultsList = await Future.wait(searchTasks);
    final allResults = resultsList.expand((x) => x).toList();

    // Ordenar por relevancia (puntuación de coincidencia)
    // Aplicamos un desempate por distancia si el puntaje es igual
    allResults.sort((a, b) {
      int scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      
      if (a.distance != null && b.distance != null) {
        return a.distance!.compareTo(b.distance!);
      }
      return 0;
    });

    return allResults;
  }

  Future<Map<String, List<String>>> _analyzeQueryWithGemini(
    String query, {
    bool isAdmin = false,
  }) async {
    try {
      final categoriesList =
          'hospedaje, picás, mercado, chambas, secret_vault, random${isAdmin ? ", mensajes" : ""}';
      final prompt = '''
Eres el núcleo de inteligencia de Lambda App, un sistema táctico para técnicos de telecomunicaciones en Chile.
Analiza la siguiente consulta: "$query"

Tu objetivo es determinar la INTENCIÓN real detrás de las palabras, interpretando tanto LENGUAJE NEUTRO como JERGA CHILENA profunda (calle y técnica).

1. Identifica categorías probables: $categoriesList.
2. Genera palabras clave NORMALIZADAS.
   - Mapeo de contexto (Lenguaje Neutro y Jerga Chilena):
     * COMIDA: "tengo hambre, buscar comida, donde almorzar, bajón, picada, picá, tentempié, mascada, casino, fonda, completo, lomo, bajonazo, quiero comer, restaurante, fuente de soda, bajonear".
       -> cat: [picás], keywords: [comida, almuerzo, completo, sandwich, restaurante, bajon, picada, cena, hambre]
     * HOSPEDAJE: "tengo sueño, donde dormir, buscar hotel, alojamiento, hostal, pension, residencial, hosteria, dormir, tuto, nono, pal sobre, pernoctar, descansar, cama, pieza, cansado, estoy muerto, necesito descansar".
       -> cat: [hospedaje], keywords: [hospedaje, hotel, cama, dormir, pieza, pension, alojamiento, hostal, descansar, tuto, sueño]
     * TRABAJO/PEGA: "buscar trabajo, empleos, pituto, pega, chamba, laburo, movida, instalación, terreno, planta externa, torre, técnico, contrato, instalar antena, fusionar fibra, necesito lucas".
       -> cat: [chambas], keywords: [trabajo, empleo, instalacion, torre, tecnico, pituto, laburo, chamba, pega]
     * MERCADO/VENTAS: "comprar herramientas, vender tester, ferretería, vendo, compro, permuta, cambio, cachureo, feria, persa, fusionadora, alicate, pelacables, materiales, bodega, insumos".
       -> cat: [mercado], keywords: [venta, compro, herramienta, tester, fusionadora, alicate, pelacables, mercado, ferreteria, insumos]
     * SEGURIDAD/SECRETOS: "hack, truco, secreto, movida, lambda, martian, bypass, clave, acceso, vault, truquito, modo admin, restricción, desbloqueo".
       -> cat: [secret_vault], keywords: [hack, tip, secreto, bypass, acceso, vault, clave, martian]
     * INFORMACIÓN/RANDOM: "noticias, clima, meme, webeo, info, santiago, regiones, que pasa, actualidad, humor, chiste, temperatura".
       -> cat: [random], keywords: [random, noticias, clima, humor, info, actualidad]

3. Detecta si el usuario busca algo "CERCA" (Proximity Intent).
   - Ej: "cerca de mi", "aqui al lado", "lo mas cercano", "en esta zona", "por aca", "al toque", "donde estoy", "cercano".

Responde ESTRICTAMENTE en JSON:
{"categories": ["cat1", "cat2"], "keywords": ["palabra1", "palabra2"], "proximityIntent": true/false}

REGLAS DE ORO:
- Entiende el contexto técnico: si dice "fibra", busca en mercado o chambas.
- Si dice "tuto" o "sueño", es HOSPEDAJE.
- Si dice "bajón", es PICÁS.
- Si la consulta es neutra ("Donde hay un hotel"), mapea correctamente a [hospedaje].
- Sé extremadamente sensible a la jerga de terreno de los técnicos chilenos.
''';
      final response = await _model.generateContent([Content.text(prompt)]);
      var text = response.text?.trim() ?? '{}';

      // Limpieza de JSON si Gemini añade bloques de código
      if (text.startsWith('```json')) {
        text = text.substring(7, text.length - 3).trim();
      } else if (text.startsWith('```')) {
        text = text.substring(3, text.length - 3).trim();
      }

      final data = jsonDecode(text);
      return {
        'categories': List<String>.from(data['categories'] ?? []),
        'keywords': List<String>.from(data['keywords'] ?? []),
        'proximityIntent': [data['proximityIntent'] == true ? 'true' : 'false'],
      };
    } catch (e) {
      debugPrint('Search Gemini Error: $e');
      return {'categories': [], 'keywords': [], 'proximityIntent': ['false']};
    }
  }

  String _removeDiacritics(String str) {
    var withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÖØòóôõöøÈÉÊËèéêëÇçÌÍÎÏìíîïÙÚÛÜùúûüÿÑñ';
    var withoutDia = 'AAAAAAaaaaaaOOOOOOooooooEEEEeeeeCcIIIIiiiiUUUUuuuuyNn';
    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }
    return str;
  }

  Future<List<SemanticResult>> _searchCollection(
    String collectionPath,
    String source,
    String originalQuery,
    List<String> keywords,
    local_coords.LatLng? userLocation, {
    bool isIntentCategory = false,
    bool proximityIntent = false,
  }) async {
    try {
      final snap = await _firestore.collection(collectionPath).limit(200).get();
      final results = <SemanticResult>[];

      for (var doc in snap.docs) {
        final data = doc.data();
        final rawTitle = data['title'] ?? data['nombre'] ?? data['authorName'] ?? '';
        final title = _removeDiacritics(rawTitle.toString().toLowerCase());
        
        final contentText = _removeDiacritics(data.values.join(' ').toLowerCase());

        double score = 0.0;
        
        // 0. Bono por Intención de Categoría (Prioridad máxima)
        if (isIntentCategory) {
          score += 5.0;
        }

        final q = _removeDiacritics(originalQuery.toLowerCase());

        // Proximidad (si aplica)
        double? distance;
        local_coords.LatLng? itemCoords;
        if (data['coordinates'] != null && data['coordinates'] is GeoPoint) {
          final gp = data['coordinates'] as GeoPoint;
          itemCoords = local_coords.LatLng(gp.latitude, gp.longitude);
          if (userLocation != null) {
            distance = _calculateDistance(
              userLocation.latitude,
              userLocation.longitude,
              gp.latitude,
              gp.longitude,
            );
          }
        }

        // 1. Alta relevancia si la consulta está en el título (exacta o parcial)
        if (title.isNotEmpty && title == q) {
          score += 3.0;
        } else if (title.isNotEmpty && title.contains(q)) {
          score += 1.5;
        }

        // 2. Coincidencia completa en el contenido
        if (contentText.contains(q)) {
          score += 1.0;
        }

        // 3. Coincidencia de palabras clave extraídas por Gemini
        if (keywords.isNotEmpty) {
           int keywordMatches = 0;
           for (var kw in keywords) {
             final kwLower = _removeDiacritics(kw.toLowerCase());
             if (contentText.contains(kwLower)) {
               keywordMatches++;
               if (title.contains(kwLower)) {
                 score += 0.8; // Más peso si está en el título
               } else {
                 score += 0.4;
               }
             }
           }
           // Bonus por multi-match de keywords
           if (keywordMatches > 1) {
             score += (keywordMatches * 0.2);
           }
        }

        // 4. Bonus de Proximidad Táctica 📡
        if (distance != null) {
          double proximityBoost = 0.0;
          if (distance < 5.0) {
            proximityBoost = 2.0; // Muy cerca (<5km)
          } else if (distance < 20.0) {
            proximityBoost = 1.0; // Cerca (<20km)
          } else if (distance < 100.0) {
            proximityBoost = 0.5; // En la zona
          }
          
          // Si el usuario explícitamente pidió "cerca", el boost de proximidad es RADICAL 📡
          if (proximityIntent) {
            proximityBoost *= 5.0; // Boost masivo para que la distancia mande
            if (distance < 2.0) score += 10.0; // Jackpot si está a menos de 2km
          }
          
          score += proximityBoost;
        }

        if (score > 0) {
          results.add(
            SemanticResult(
              id: doc.id,
              title: rawTitle.toString().isNotEmpty ? rawTitle.toString() : 'Resultado',
              content:
                  data['description'] ??
                  data['location'] ??
                  data['locationName'] ??
                  data['content'] ??
                  '',
              source: source,
              score: score,
              distance: distance,
              coordinates: itemCoords,
            ),
          );
        }
      }
      return results;
    } catch (e) {
      debugPrint('Search Error in $collectionPath: $e');
      return [];
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
  }

  Future<List<SemanticResult>> _searchMessages(
    String query,
    List<String> keywords,
  ) async {
    try {
      final queryLower = _removeDiacritics(query.toLowerCase());
      // Limitamos a los últimos 1000 mensajes por performance
      final snap =
          await _firestore
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(1000)
              .get();

      final results = <SemanticResult>[];
      for (var doc in snap.docs) {
        final data = doc.data();
        final rawBody = (data['body'] as String?)?.toLowerCase() ?? '';
        final rawSubject = (data['subject'] as String?)?.toLowerCase() ?? '';
        
        final body = _removeDiacritics(rawBody);
        final subject = _removeDiacritics(rawSubject);
        final senderId = data['senderId'] ?? 'unknown';

        double score = 0.0;
        if (subject.isNotEmpty && subject == queryLower) {
          score += 3.0;
        } else if (subject.isNotEmpty && subject.contains(queryLower)) score += 1.5;
        
        if (body.contains(queryLower)) score += 1.0;

        for (var kw in keywords) {
          var kwLower = _removeDiacritics(kw.toLowerCase());
          if (subject.contains(kwLower)) score += 0.8;
          if (body.contains(kwLower)) score += 0.4;
        }

        if (score > 0) {
          results.add(
            SemanticResult(
              id: doc.id,
              title: 'Mensaje de $senderId',
              content: rawSubject.isNotEmpty ? '[RE: $rawSubject] $rawBody' : rawBody,
              source: 'mensajes',
              score: score,
            ),
          );
        }
      }
      return results;
    } catch (e) {
      debugPrint('Search Messages Error: $e');
      return [];
    }
  }
}
