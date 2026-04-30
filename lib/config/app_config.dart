// lib/config/app_config.dart

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
  static const String defaultMapsApiKey = '';

  /// API key para Weather Service.
  static String get weatherApiKey =>
      const String.fromEnvironment('WEATHER_API_KEY', defaultValue: '');

  /// API key para Gemini Service.
  static String get geminiApiKey =>
      const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  /// Valida configuraciones mínimas al arranque. Lanza si falta algo crítico.
  static void validate() {
    assert(mapsApiKey.isNotEmpty, 'MAPS_API_KEY no puede estar vacío');
  }
}
