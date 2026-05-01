import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:lambda_app/config/app_config.dart';
import 'package:lambda_app/providers/semantic_search_provider.dart';
import 'package:flutter/foundation.dart';

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
  }) async {
    // 1. Analizar intención y extraer palabras clave normalizadas con Gemini
    final analysis = await _analyzeQueryWithGemini(query, isAdmin: isAdmin);
    final List<String> categories = analysis['categories'] ?? [];
    final List<String> keywords = analysis['keywords'] ?? [];

    final List<Future<List<SemanticResult>>> searchTasks = [];

    // Si Gemini no detectó categorías claras, buscar en todo por defecto
    bool searchAll = categories.isEmpty;

    if (searchAll || categories.contains('hospedaje')) {
      searchTasks.add(
        _searchCollection('lodging_tracker', 'hospedaje', query, keywords),
      );
    }
    if (searchAll ||
        categories.contains('picás') ||
        categories.contains('comida')) {
      searchTasks.add(
        _searchCollection('food_tracker', 'picás', query, keywords),
      );
    }
    if (searchAll || categories.contains('mercado')) {
      searchTasks.add(
        _searchCollection('market_items', 'mercado', query, keywords),
      );
    }
    if (searchAll ||
        categories.contains('chambas') ||
        categories.contains('trabajo')) {
      searchTasks.add(_searchCollection('chambas', 'chambas', query, keywords));
    }
    if (searchAll || categories.contains('secret_vault')) {
      searchTasks.add(
        _searchCollection('hacks_vault', 'tips_hacks', query, keywords),
      );
      searchTasks.add(
        _searchCollection('nave_vault', 'la_nave', query, keywords),
      );
    }
    if (searchAll || categories.contains('random')) {
      searchTasks.add(
        _searchCollection('random_board', 'random', query, keywords),
      );
    }

    // Búsqueda de Auditoría de Mensajes (Solo para Admins)
    if (isAdmin &&
        (searchAll ||
            categories.contains('mensajes') ||
            categories.contains('auditoria'))) {
      searchTasks.add(_searchMessages(query, keywords));
    }

    final resultsList = await Future.wait(searchTasks);
    final allResults = resultsList.expand((x) => x).toList();

    // Ordenar por relevancia (puntuación de coincidencia)
    allResults.sort((a, b) => b.score.compareTo(a.score));

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
Analiza esta consulta de usuario en una app comunitaria (telecomunicaciones, picadas chilenas, empleos, herramientas): "$query"
1. Identifica las categorías relevantes de esta lista: $categoriesList.
2. Genera una lista de palabras clave NORMALIZADAS, incluyendo la palabra original, sinónimos chilenos, jerga técnica y raíces.
Ejemplos:
- "pega" -> ["trabajo", "pega", "empleo", "chamba", "contrato"]
- "fibra" -> ["fibra", "fo", "optica", "dwdm", "corte", "falla"]
- "comida" -> ["comida", "picá", "almuerzo", "restaurante", "comer"]

Responde ESTRICTAMENTE en formato JSON:
{"categories": ["cat1", "cat2"], "keywords": ["word1", "word2"]}
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
      };
    } catch (e) {
      debugPrint('Search Gemini Error: $e');
      return {'categories': [], 'keywords': []};
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
  ) async {
    try {
      final snap = await _firestore.collection(collectionPath).limit(200).get();
      final results = <SemanticResult>[];

      for (var doc in snap.docs) {
        final data = doc.data();
        final rawTitle = data['title'] ?? data['nombre'] ?? data['authorName'] ?? '';
        final title = _removeDiacritics(rawTitle.toString().toLowerCase());
        
        final contentText = _removeDiacritics(data.values.join(' ').toLowerCase());

        double score = 0.0;
        final q = _removeDiacritics(originalQuery.toLowerCase());

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
