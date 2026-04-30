import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

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
  // Usaremos una API gratuita (OpenWeatherMap) con la key del usuario
  // Por ahora, si falla, devolvemos un mock realista para Chile.

  Future<WeatherData?> getWeather(double lat, double lon) async {
    try {
      final apiKey = AppConfig.weatherApiKey;
      final url = 'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=es';
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
