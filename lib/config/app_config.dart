// lib/config/app_config.dart

/// Configuración global de la aplicación (API keys, feature flags, etc.).
class AppConfig {
  AppConfig._();

  /// API key para Google Maps.
  /// En producción: flutter run --dart-define=MAPS_API_KEY=tu_key
  /// Si no se pasa, usa [defaultMapsApiKey] (solo desarrollo).
  static String get mapsApiKey =>
      String.fromEnvironment('MAPS_API_KEY', defaultValue: defaultMapsApiKey);

  /// Clave por defecto (desarrollo/local). En producción usar --dart-define.
  static const String defaultMapsApiKey =
      'AIzaSyDqxltfJNA6I_sqFiTpmRHn4ApiC2hh6Z8';

  /// Valida configuraciones mínimas al arranque. Lanza si falta algo crítico.
  static void validate() {
    assert(mapsApiKey.isNotEmpty, 'MAPS_API_KEY no puede estar vacío');
  }
}
