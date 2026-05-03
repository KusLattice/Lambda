import 'dart:convert';

import 'package:http/http.dart' as http;

/// Resultado de una búsqueda por dirección (Geocoding API).
class GeocodingResult {
  const GeocodingResult({
    required this.lat,
    required this.lng,
    this.formattedAddress,
  });

  final double lat;
  final double lng;
  final String? formattedAddress;
}

/// Servicio para convertir direcciones en coordenadas (Google Geocoding API).
/// Requiere activar "Geocoding API" en Google Cloud Console.
class GeocodingService {
  GeocodingService({required this.apiKey});

  final String apiKey;

  /// Obtiene lat/lng para una dirección o lugar. Retorna null si no hay resultados o falla.
  Future<GeocodingResult?> geocode(String address) async {
    if (address.trim().isEmpty || apiKey.isEmpty) return null;

    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': address.trim(),
      'key': apiKey,
    });

    final response = await http.get(uri);

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>?;
    if (json == null) return null;

    final status = json['status'] as String?;
    if (status != 'OK') {
      throw Exception(
        json['error_message'] ??
            'Error $status (Asegúrate de que la API esté habilitada en Google Cloud)',
      );
    }

    final results = json['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final geometry = first['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    if (location == null) return null;

    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final formattedAddress = first['formatted_address'] as String?;

    return GeocodingResult(
      lat: lat,
      lng: lng,
      formattedAddress: formattedAddress,
    );
  }

  /// Obtiene la dirección aproximada dada una coordenada (Reverse Geocoding).
  Future<GeocodingResult?> reverseGeocode(double lat, double lng) async {
    if (apiKey.isEmpty) return null;
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '$lat,$lng',
      'key': apiKey,
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>?;
    if (json == null) return null;

    final status = json['status'] as String?;
    if (status != 'OK') {
      throw Exception(
        json['error_message'] ??
            'Error $status (Asegúrate de que la API esté habilitada en Google Cloud)',
      );
    }

    final results = json['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final formattedAddress = first['formatted_address'] as String?;

    return GeocodingResult(
      lat: lat,
      lng: lng,
      formattedAddress: formattedAddress,
    );
  }
}
