import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:lambda_app/config/app_config.dart';
import 'package:lambda_app/providers/theme_provider.dart';

class WeatherBanner extends ConsumerStatefulWidget {
  const WeatherBanner({super.key});

  @override
  ConsumerState<WeatherBanner> createState() => _WeatherBannerState();
}

class _WeatherBannerState extends ConsumerState<WeatherBanner> {
  _WeatherData? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    try {
      // 1. Obtener ubicación
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'GPS desactivado';

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        throw 'Permiso de ubicación denegado permanentemente';
      }

      final pos =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
            ),
          ).timeout(
            const Duration(seconds: 4),
            onTimeout: () => throw 'Tiempo expirado GPS',
          );

      // 2. Llamar Open-Meteo
      final lat = pos.latitude;
      final lon = pos.longitude;
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,apparent_temperature,relative_humidity_2m,'
        'precipitation,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,'
        'uv_index,precipitation_probability'
        '&daily=sunrise,sunset,uv_index_max'
        '&timezone=auto'
        '&forecast_days=1',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw 'API error ${res.statusCode}';

      final json = jsonDecode(res.body);
      final current = json['current'];
      final daily = json['daily'];
      final elevation = (json['elevation'] as num?)?.toDouble() ?? pos.altitude;

      if (mounted) {
        setState(() {
          _data = _WeatherData(
            temp: (current['temperature_2m'] as num).toDouble(),
            feelsLike: (current['apparent_temperature'] as num).toDouble(),
            humidity: (current['relative_humidity_2m'] as num).toInt(),
            pressure: (current['pressure_msl'] as num).toDouble(),
            windSpeed: (current['wind_speed_10m'] as num).toDouble(),
            windDir: (current['wind_direction_10m'] as num).toInt(),
            uvIndex: (current['uv_index'] as num).toDouble(),
            weatherCode: (current['weather_code'] as num).toInt(),
            rainProb:
                (current['precipitation_probability'] as num?)?.toInt() ?? 0,
            altitude: elevation,
            sunrise: _parseTime(daily['sunrise']?[0] as String? ?? ''),
            sunset: _parseTime(daily['sunset']?[0] as String? ?? ''),
          );
        });
      }

      // 3. Llamar a Google Air Quality API
      final urlAqi = Uri.parse(
        'https://airquality.googleapis.com/v1/currentConditions:lookup?key=${AppConfig.mapsApiKey}',
      );
      final aqiRes = await http
          .post(
            urlAqi,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'location': {'latitude': lat, 'longitude': lon},
            }),
          )
          .timeout(const Duration(seconds: 15));

      int? aqiValue;
      if (aqiRes.statusCode == 200) {
        final aqiJson = jsonDecode(aqiRes.body);
        if (aqiJson['indexes'] != null && aqiJson['indexes'].isNotEmpty) {
          aqiValue = aqiJson['indexes'][0]['aqi'];
        }
      }

      if (mounted && _data != null) {
        setState(() {
          _data = _data!.copyWith(aqi: aqiValue);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Extrae "HH:MM" de un string ISO8601 como "2024-01-01T06:30"
  String _parseTime(String iso) {
    if (iso.isEmpty) return '--:--';
    try {
      return iso.split('T')[1].substring(0, 5);
    } catch (_) {
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4D3E), // Verde técnico sólido total
        border: Border(
          bottom: BorderSide(color: theme.accent.withOpacity(0.3), width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(child: _buildContent(theme)),
    );
  }

  Widget _buildContent(LambdaTheme theme) {
    if (_loading) {
      return SizedBox(
        height: 60,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(theme.accent),
            ),
          ),
        ),
      );
    }

    if (_error != null || _data == null) {
      return SizedBox(
        height: 60,
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: Colors.redAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Datos de Clima no disponibles.\nOtorga permisos de ubicación y presiona recargar.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'Courier',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadWeather();
              },
              child: Icon(Icons.refresh, color: theme.accent, size: 26),
            ),
          ],
        ),
      );
    }

    final d = _data!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Row(
        children: [
          // --- Izquierda: Icono Grande + Temp Grande ---
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _weatherEmoji(d.weatherCode),
                    style: const TextStyle(fontSize: 44),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${d.temp.round()}°',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Inter',
                      letterSpacing: -2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Divisor sutil vertical
          Container(
            height: 40,
            width: 1,
            color: Colors.white10,
          ),
          const SizedBox(width: 16),

          // --- Derecha: Grilla de Métricas Técnicas ---
          Expanded(
            flex: 6,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _cyberMetric('ST', '${d.feelsLike.round()}°'),
                    _cyberMetric('HUM', '${d.humidity}%'),
                    _cyberMetric('LLUVIA', '${d.rainProb}%'),
                    _cyberMetric('WIND', '${d.windSpeed.round()}k/h'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _cyberMetric('ALT', '${d.altitude.round()}m'),
                    _cyberMetric('PRES', '${d.pressure.round()}h'),
                    _cyberMetric('UV', '${d.uvIndex.round()}'),
                    _cyberMetric('AQI', '${d.aqi ?? 33}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cyberMetric(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 9,
            fontFamily: 'Courier',
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontFamily: 'Courier',
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Dirección del viento en cardinal a partir de grados
  String _windDirCardinal(int deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return dirs[((deg % 360) / 45).round() % 8];
  }

  /// Emoji según WMO weather code
  String _weatherEmoji(int code) {
    if (code == 0) return '☀️';
    if (code <= 2) return '🌤';
    if (code == 3) return '☁️';
    if (code <= 49) return '🌫';
    if (code <= 59) return '🌦';
    if (code <= 69) return '🌧';
    if (code <= 79) return '🌨';
    if (code <= 82) return '🌧';
    if (code <= 84) return '🌨';
    if (code <= 99) return '⛈';
    return '🌡';
  }
}

class _WeatherData {
  final double temp;
  final double feelsLike;
  final int humidity;
  final double pressure;
  final double windSpeed;
  final int windDir;
  final double uvIndex;
  final int weatherCode;
  final int rainProb;
  final double altitude;
  final String sunrise;
  final String sunset;
  final int? aqi;

  const _WeatherData({
    required this.temp,
    required this.feelsLike,
    required this.humidity,
    required this.pressure,
    required this.windSpeed,
    required this.windDir,
    required this.uvIndex,
    required this.weatherCode,
    required this.rainProb,
    required this.altitude,
    required this.sunrise,
    required this.sunset,
    this.aqi,
  });

  _WeatherData copyWith({int? aqi}) {
    return _WeatherData(
      temp: temp,
      feelsLike: feelsLike,
      humidity: humidity,
      pressure: pressure,
      windSpeed: windSpeed,
      windDir: windDir,
      uvIndex: uvIndex,
      weatherCode: weatherCode,
      rainProb: rainProb,
      altitude: altitude,
      sunrise: sunrise,
      sunset: sunset,
      aqi: aqi ?? this.aqi,
    );
  }
}
