// lib/config/app_config.dart
import 'package:flutter/foundation.dart';


/// Configuración global de la aplicación (API keys, feature flags, etc.).
class AppConfig {
  AppConfig._();

  /// API key para Google Maps.
  /// En producción: flutter run --dart-define=MAPS_API_KEY=tu_key
  /// Si no se pasa, usa [defaultMapsApiKey] (solo desarrollo).
  static String get mapsApiKey =>
      const String.fromEnvironment('MAPS_API_KEY', defaultValue: defaultMapsApiKey);

  /// Clave por defecto (desarrollo/local). En producción usar --dart-define.
  /// MUST be passed via --dart-define=MAPS_API_KEY=... Nunca comitear API keys.
  static const String defaultMapsApiKey = 'AIzaSyDqxltfJNA6I_sqFiTpmRHn4ApiC2hh6Z8';

  /// API key para Weather Service.
  static String get weatherApiKey =>
      const String.fromEnvironment('WEATHER_API_KEY', defaultValue: '');

  /// API key para Gemini Service.
  static String get geminiApiKey =>
      const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  static bool get hasGeminiKey => geminiApiKey.isNotEmpty;
  static bool get hasMapsKey => mapsApiKey.isNotEmpty;

  /// Valida configuraciones mínimas al arranque.
  static void validate() {
    if (!hasMapsKey) {
      debugPrint(
        '[AppConfig] ⚠️ MAPS_API_KEY está vacío. '
        'Usa --dart-define=MAPS_API_KEY=... para habilitar Maps y AQI.',
      );
    }
    if (weatherApiKey.isEmpty) {
      debugPrint(
        '[AppConfig] ⚠️ WEATHER_API_KEY está vacío. '
        'Usa --dart-define=WEATHER_API_KEY=... para habilitar WeatherService.',
      );
    }
    if (!hasGeminiKey) {
      debugPrint(
        '[AppConfig] ⚠️ GEMINI_API_KEY está vacío. '
        'Usa --dart-define=GEMINI_API_KEY=... para habilitar búsqueda IA.',
      );
    }
  }
}
