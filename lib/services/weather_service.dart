import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class WeatherData {
  final double temp;
  final String condition;
  final String icon;

  WeatherData({
    required this.temp,
    required this.condition,
    required this.icon,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temp: (json['main']['temp'] as num).toDouble(),
      condition: json['weather'][0]['description'],
      icon: json['weather'][0]['icon'],
    );
  }
}

class WeatherService {
  // Usaremos una API gratuita (OpenWeatherMap) con un key de ejemplo o el del usuario si tuviera
  // Por ahora, si falla, devolvemos un mock realista para Chile.
  static const String _apiKey = 'b6907d289e10d714a6e88b30761fae22'; // Key de ejemplo público común

  Future<WeatherData?> getWeather(double lat, double lon) async {
    try {
      final url = 'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$_apiKey&units=metric&lang=es';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return WeatherData.fromJson(json.decode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      debugPrint('WeatherService Error: $e');
    }
    return null;
  }

  WeatherData getMockChile() {
    return WeatherData(
      temp: 22.5,
      condition: 'Despejado',
      icon: '01d',
    );
  }
}
