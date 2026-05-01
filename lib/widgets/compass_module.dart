// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

// ──────────────────────────────────────────────────────────────────────────────
// COMPASS MODULE — widget para el dashboard
// ──────────────────────────────────────────────────────────────────────────────
class CompassModule extends StatefulWidget {
  const CompassModule({super.key});

  @override
  State<CompassModule> createState() => _CompassModuleState();
}

class _CompassModuleState extends State<CompassModule>
    with SingleTickerProviderStateMixin {
  // ── Heading ─────────────────────────────────────────────────────────────────
  double _heading = 0;
  double _displayHeading = 0; // suavizado
  bool _sensorAvailable = true;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  late AnimationController _needleCtrl;
  final _headingStreamController = StreamController<double>.broadcast();

  // ── GPS ──────────────────────────────────────────────────────────────────────
  double? _lat, _lon;
  double _accuracy = 0;
  double _speed = 0; // m/s
  StreamSubscription<Position>? _gpsSub;

  @override
  void initState() {
    super.initState();

    // Animación suave de la aguja
    _needleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Se recomienda iniciar primero GPS (permisos de ubicación) antes que la brújula
    _initSensors();
  }

  Future<void> _initSensors() async {
    // 1. Obtener acceso a GPS/Ubicación
    final hasLocation = await _initGPS();

    // 2. Inicializar brújula una vez resuelto el GPS
    _initCompass(hasLocation);
  }

  void _initCompass(bool hasLocationPermission) {
    debugPrint('Iniciando brújula... Permisos de GPS: $hasLocationPermission');
    var compassStream = FlutterCompass.events;

    if (compassStream == null) {
      debugPrint(
        'Error crítico: FlutterCompass.events retornó null. Dispositivo sin sensor magnético soportado.',
      );
      if (mounted) setState(() => _sensorAvailable = false);
      return;
    }

    _compassSub = compassStream.listen(
      (event) {
        if (!mounted) return;
        final raw = event.heading ?? 0;
        _headingStreamController.add(raw);
        final diff = _angleDiff(_heading, raw);

        if (!_sensorAvailable) {
          debugPrint('Sensor de brújula detectado activo.');
          setState(() => _sensorAvailable = true);
        }

        _needleCtrl.forward(from: 0);
        setState(() {
          _heading = raw;
          _displayHeading = (_displayHeading + diff) % 360;
        });
      },
      onError: (error) {
        debugPrint('Compass Error fatal: $error');
        if (mounted) setState(() => _sensorAvailable = false);
      },
      cancelOnError: false,
    );

    // Timeout de seguridad: Si en 4 segundos no recibimos datos de heading
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _heading == 0) {
        debugPrint(
          'Timeout de Brújula excedido (4s). Activando fallback manual (sensors_plus).',
        );
        _compassSub?.cancel();
        _compassSub = null;
        _initFallbackCompass();
      }
    });
  }

  void _initFallbackCompass() {
    bool hasData = false;
    _magSub = magnetometerEventStream().listen(
      (event) {
        if (!mounted) return;
        hasData = true;

        // Si el hardware devuelve puro ruido falso o ceros absolutos, lo matamos.
        if (event.x == 0 && event.y == 0) {
          debugPrint(
            'Lectura magnética en cero absoluto. Anulando brújula falsificada.',
          );
          if (mounted) setState(() => _sensorAvailable = false);
          _magSub?.cancel();
          return;
        }

        // Asumiendo celular plano en la mesa
        double rad = atan2(event.y, event.x);
        double raw = (rad * 180 / pi);
        // Ajuste de sistema de coordenadas para alinear el norte con el eje Y
        raw = (raw - 90) * -1;
        raw = (raw + 360) % 360;
        _headingStreamController.add(raw);

        final diff = _angleDiff(_heading, raw);

        if (!_sensorAvailable) {
          setState(() => _sensorAvailable = true);
        }

        _needleCtrl.forward(from: 0);
        setState(() {
          _heading = raw;
          _displayHeading = (_displayHeading + diff) % 360;
        });
      },
      onError: (e) {
        debugPrint('Fallback Compass Error: $e');
        if (mounted) setState(() => _sensorAvailable = false);
      },
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !hasData) {
        debugPrint('Magnetómetro nativo inoperativo. Sensor indisponible.');
        setState(() => _sensorAvailable = false);
      }
    });
  }

  Future<bool> _initGPS() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return false;
      }

      _gpsSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 1,
            ),
          ).listen(
            (pos) {
              if (!mounted) return;
              setState(() {
                _lat = pos.latitude;
                _lon = pos.longitude;
                _accuracy = pos.accuracy;
                _speed = pos.speed; // m/s
              });
            },
            onError: (e) {
              debugPrint('GPS Stream Error: $e');
            },
          );

      return true;
    } catch (e) {
      debugPrint('Init GPS Error: $e');
      return false;
    }
  }

  /// Diferencia angular mínima entre a y b (–180 a 180)
  double _angleDiff(double a, double b) {
    double diff = (b - a + 540) % 360 - 180;
    return diff;
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _magSub?.cancel();
    _gpsSub?.cancel();
    _headingStreamController.close();
    _needleCtrl.dispose();
    super.dispose();
  }

  // ── 16 punto cardinal ────────────────────────────────────────────────────────
  String _toCardinal16(double deg) {
    const pts = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSO',
      'SO',
      'OSO',
      'O',
      'ONO',
      'NO',
      'NNO',
    ];
    final idx = ((deg % 360) / 22.5).round() % 16;
    return pts[idx];
  }

  void _openFullCompass() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FullCompassSheet(
        headingStream: _headingStreamController.stream,
        lat: _lat,
        lon: _lon,
        accuracy: _accuracy,
        speed: _speed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_sensorAvailable) {
      return GestureDetector(onTap: _openFullCompass, child: _NoSensorWidget());
    }

    final cardinal = _toCardinal16(_heading);
    final azimut = _heading.toStringAsFixed(1);

    return GestureDetector(
      onTap: _openFullCompass,
      child: FittedBox(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Dial ──────────────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _needleCtrl,
              builder: (context, child) {
                return SizedBox(
                  width: 80,
                  height: 80,
                  child: CustomPaint(painter: _DialPainter(_displayHeading)),
                );
              },
            ),
            const SizedBox(height: 3),
            // ── Cardinal ─────────────────────────────────────────────────────
            Text(
              cardinal,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            // ── Azimut ───────────────────────────────────────────────────────
            Text(
              '$azimut°',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            // ── GPS coords mini ───────────────────────────────────────────────
            if (_lat != null)
              Text(
                '${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)}',
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 8,
                  fontFamily: 'monospace',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// DIAL PAINTER (mini, en el dashboard)
// ──────────────────────────────────────────────────────────────────────────────
class _DialPainter extends CustomPainter {
  final double heading;
  _DialPainter(this.heading);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 3;

    // Fondo
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFF0D1117),
    );
    // Borde exterior
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Ticks cada 45° (primarios)
    for (double angle = 0; angle < 360; angle += 45) {
      final rad = (angle - heading) * pi / 180;
      final isCard = angle % 90 == 0;
      final inner = r - (isCard ? 10 : 6);
      final outer = r - 1;
      canvas.drawLine(
        Offset(cx + inner * sin(rad), cy - inner * cos(rad)),
        Offset(cx + outer * sin(rad), cy - outer * cos(rad)),
        Paint()
          ..color = isCard
              ? Colors.greenAccent.withValues(alpha: 0.9)
              : Colors.white30
          ..strokeWidth = isCard ? 1.5 : 1.0,
      );
    }

    // Letras cardinales N/E/S/O
    const cardAngles = {'N': 0.0, 'E': 90.0, 'S': 180.0, 'O': 270.0};
    for (final e in cardAngles.entries) {
      final rad = (e.value - heading) * pi / 180;
      final labelR = r - 17;
      final tp = TextPainter(
        text: TextSpan(
          text: e.key,
          style: TextStyle(
            color: e.key == 'N' ? Colors.redAccent : Colors.white60,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          cx + labelR * sin(rad) - tp.width / 2,
          cy - labelR * cos(rad) - tp.height / 2,
        ),
      );
    }

    // Aguja Norte (roja)
    final northPaint = Paint()
      ..color = Colors.red.shade600
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(
        cx + (r - 14) * sin(-heading * pi / 180),
        cy - (r - 14) * cos(-heading * pi / 180),
      ),
      northPaint,
    );

    // Aguja Sur (blanca)
    canvas.drawLine(
      Offset(cx, cy),
      Offset(
        cx + (r - 20) * sin((180 - heading) * pi / 180),
        cy - (r - 20) * cos((180 - heading) * pi / 180),
      ),
      Paint()
        ..color = Colors.white38
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Centro
    canvas.drawCircle(Offset(cx, cy), 3.5, Paint()..color = Colors.greenAccent);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.heading != heading;
}

// ──────────────────────────────────────────────────────────────────────────────
// FULL COMPASS SHEET — pantalla completa HUD al hacer tap
// ──────────────────────────────────────────────────────────────────────────────
class _FullCompassSheet extends StatefulWidget {
  final Stream<double>? headingStream;
  final double? lat;
  final double? lon;
  final double accuracy;
  final double speed;

  const _FullCompassSheet({
    required this.headingStream,
    required this.lat,
    required this.lon,
    required this.accuracy,
    required this.speed,
  });

  @override
  State<_FullCompassSheet> createState() => _FullCompassSheetState();
}

class _FullCompassSheetState extends State<_FullCompassSheet>
    with SingleTickerProviderStateMixin {
  double _heading = 0;
  StreamSubscription<double>? _sub;

  // GPS local (para actualizar en la hoja también)
  double? _lat, _lon;
  double _accuracy = 0;
  double _speed = 0;
  StreamSubscription<Position>? _gpsSub;

  // Animación de glow del ring
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _lat = widget.lat;
    _lon = widget.lon;
    _accuracy = widget.accuracy;
    _speed = widget.speed;

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 3, end: 14).animate(_glowCtrl);

    _sub = widget.headingStream?.listen((heading) {
      if (!mounted) return;
      setState(() {
        _heading = heading;
      });
    });

    _initGPS();
  }

  Future<void> _initGPS() async {
    bool ok = await Geolocator.isLocationServiceEnabled();
    if (!ok) return;
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) return;

    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1,
          ),
        ).listen(
          (pos) {
            if (!mounted) return;
            setState(() {
              _lat = pos.latitude;
              _lon = pos.longitude;
              _accuracy = pos.accuracy;
              _speed = pos.speed; // Puede ser <= 0 si no se mueve
            });
          },
          onError: (e) {
            debugPrint('Error GPS Compass HUD: $e');
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _gpsSub?.cancel();
    _glowCtrl.dispose();
    super.dispose();
  }

  String _toCardinal16(double deg) {
    const pts = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSO',
      'SO',
      'OSO',
      'O',
      'ONO',
      'NO',
      'NNO',
    ];
    final idx = ((deg % 360) / 22.5).round() % 16;
    return pts[idx];
  }

  /// Formatea coordenadas en DMS (Grados°Minutos'Segundos")
  String _toDMS(double decimal, bool isLat) {
    final dir = isLat ? (decimal >= 0 ? 'N' : 'S') : (decimal >= 0 ? 'E' : 'O');
    final abs = decimal.abs();
    final deg = abs.floor();
    final min = ((abs - deg) * 60).floor();
    final sec = ((abs - deg) * 3600 - min * 60);
    return "$deg° $min' ${sec.toStringAsFixed(1)}\" $dir";
  }

  String _signalBars(double accuracy) {
    if (accuracy <= 5) {
      return '▂▄▆█ EXCELENTE (${accuracy.toStringAsFixed(0)}m)';
    }
    if (accuracy <= 15) return '▂▄▆░ BUENA (${accuracy.toStringAsFixed(0)}m)';
    if (accuracy <= 30) return '▂▄░░ REGULAR (${accuracy.toStringAsFixed(0)}m)';
    return '▂░░░ DÉBIL (${accuracy.toStringAsFixed(0)}m)';
  }

  @override
  Widget build(BuildContext context) {
    final cardinal = _toCardinal16(_heading);
    final azimut = _heading.toStringAsFixed(1);
    final speedKmh = (_speed * 3.6).toStringAsFixed(1);
    final speedMs = _speed.toStringAsFixed(1);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: const Color(0xFF080C10),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.explore, color: Colors.greenAccent, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'BRÚJULA  //  NAV-TOOL',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    letterSpacing: 3,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  'λ TELECOM',
                  style: TextStyle(
                    color: Colors.greenAccent.withValues(alpha: 0.4),
                    fontSize: 10,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.greenAccent, thickness: 0.2, height: 1),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── Dial grande ─────────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _glowAnim,
                    builder: (context, child) {
                      return Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.greenAccent.withValues(alpha: 0.15),
                              blurRadius: _glowAnim.value,
                              spreadRadius: _glowAnim.value / 3,
                            ),
                          ],
                        ),
                        child: CustomPaint(
                          painter: _LargeDialPainter(_heading),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Cardinal grande ──────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        cardinal,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$azimut°',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 22,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Grid de datos ────────────────────────────────────────────
                  _DataGrid([
                    _DataCell(
                      label: 'VELOCIDAD',
                      value: '$speedKmh km/h',
                      sub: '$speedMs m/s',
                      icon: Icons.speed,
                    ),
                    _DataCell(
                      label: 'PRECISIÓN GPS',
                      value: _accuracy > 0
                          ? _signalBars(_accuracy)
                          : 'Adquiriendo…',
                      icon: Icons.gps_fixed,
                      valueSize: 9,
                    ),
                    _DataCell(
                      label: 'AZIMUT',
                      value: '$azimut°',
                      sub: 'magnético',
                      icon: Icons.rotate_right,
                    ),
                    _DataCell(
                      label: 'RUMBO INVERSO',
                      value: '${((_heading + 180) % 360).toStringAsFixed(1)}°',
                      sub: _toCardinal16((_heading + 180) % 360),
                      icon: Icons.swap_vert,
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // ── Coordenadas ──────────────────────────────────────────────
                  if (_lat != null) ...[
                    _SectionHeader('COORDENADAS GPS'),
                    const SizedBox(height: 8),
                    _CoordCard(lat: _lat!, lon: _lon!, toDMS: _toDMS),
                    const SizedBox(height: 16),
                  ],

                  // ── Barra de referencia de azimut ─────────────────────────────
                  _SectionHeader('REFERENCIA DE AZIMUT'),
                  const SizedBox(height: 8),
                  _AzimutBar(heading: _heading),

                  const SizedBox(height: 16),

                  // ── Inclinómetro de burbuja ──────────────────────────────────
                  _SectionHeader('INCLINÓMETRO (Acelerómetro)'),
                  const SizedBox(height: 8),
                  const _BubbleLevelWidget(),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// LARGE DIAL PAINTER
// ──────────────────────────────────────────────────────────────────────────────
class _LargeDialPainter extends CustomPainter {
  final double heading;
  _LargeDialPainter(this.heading);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 6;

    // Fondo radial
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF0A1628), const Color(0xFF050C18)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, bgPaint);

    // Borde doble
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r - 6,
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Ticks cada 5° (pequeños), 10° (medianos), 30° (grandes)
    for (double angle = 0; angle < 360; angle += 5) {
      final rad = (angle - heading) * pi / 180;
      final is30 = angle % 30 == 0;
      final is10 = angle % 10 == 0;
      final tickLen = is30
          ? 14.0
          : is10
          ? 9.0
          : 5.0;
      final strokeW = is30
          ? 1.5
          : is10
          ? 1.0
          : 0.7;
      final opacity = is30
          ? 0.8
          : is10
          ? 0.5
          : 0.25;
      final inner = r - 6 - tickLen;
      final outer = r - 6;
      canvas.drawLine(
        Offset(cx + inner * sin(rad), cy - inner * cos(rad)),
        Offset(cx + outer * sin(rad), cy - outer * cos(rad)),
        Paint()
          ..color = Colors.greenAccent.withValues(alpha: opacity)
          ..strokeWidth = strokeW,
      );
    }

    // Números cada 30° (0=N, 30, 60 ... 330)
    for (double angle = 0; angle < 360; angle += 30) {
      final rad = (angle - heading) * pi / 180;
      final labelR = r - 30;
      final label = angle == 0
          ? 'N'
          : angle == 90
          ? 'E'
          : angle == 180
          ? 'S'
          : angle == 270
          ? 'O'
          : angle.toInt().toString();

      final isMain = angle % 90 == 0;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: angle == 0
                ? Colors.red.shade400
                : isMain
                ? Colors.white70
                : Colors.white38,
            fontSize: isMain ? 13 : 9,
            fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          cx + labelR * sin(rad) - tp.width / 2,
          cy - labelR * cos(rad) - tp.height / 2,
        ),
      );
    }

    // Sombra de aguja norte
    final shadowPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawLine(
      Offset(cx, cy),
      Offset(
        cx + (r - 30) * sin(-heading * pi / 180),
        cy - (r - 30) * cos(-heading * pi / 180),
      ),
      shadowPaint,
    );

    // Aguja Norte (roja, con punta de flecha)
    _drawNeedle(canvas, cx, cy, r - 30, -heading, Colors.red.shade500, 3.5);

    // Aguja Sur (blanca)
    _drawNeedle(canvas, cx, cy, r - 40, 180 - heading, Colors.white38, 2.5);

    // Círculo central
    canvas.drawCircle(
      Offset(cx, cy),
      7,
      Paint()
        ..color = const Color(0xFF0A1628)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      7,
      Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = Colors.greenAccent);
  }

  void _drawNeedle(
    Canvas canvas,
    double cx,
    double cy,
    double length,
    double angleDeg,
    Color color,
    double strokeW,
  ) {
    final rad = angleDeg * pi / 180;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + length * sin(rad), cy - length * cos(rad)),
      Paint()
        ..color = color
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LargeDialPainter old) => old.heading != heading;
}

// ──────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ──────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: Colors.greenAccent),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: Colors.greenAccent.withValues(alpha: 0.7),
            fontSize: 10,
            letterSpacing: 2,
            fontFamily: 'monospace',
          ),
        ),
        const Spacer(),
        Container(
          height: 0.5,
          width: 80,
          color: Colors.greenAccent.withValues(alpha: 0.2),
        ),
      ],
    );
  }
}

class _DataCell {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final double valueSize;

  const _DataCell({
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
    this.valueSize = 13,
  });
}

class _DataGrid extends StatelessWidget {
  final List<_DataCell> cells;
  const _DataGrid(this.cells);

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: cells
          .map(
            (c) => Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D1520),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.1)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(c.icon, color: Colors.greenAccent, size: 10),
                      const SizedBox(width: 4),
                      Text(
                        c.label,
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 7,
                          letterSpacing: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.value,
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: c.valueSize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (c.sub != null)
                    Text(
                      c.sub!,
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _CoordCard extends StatelessWidget {
  final double lat;
  final double lon;
  final String Function(double, bool) toDMS;

  const _CoordCard({required this.lat, required this.lon, required this.toDMS});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          _CoordRow(
            label: 'LAT',
            decimal: lat.toStringAsFixed(6),
            dms: toDMS(lat, true),
          ),
          const SizedBox(height: 6),
          _CoordRow(
            label: 'LON',
            decimal: lon.toStringAsFixed(6),
            dms: toDMS(lon, false),
          ),
          const Divider(color: Colors.white12, height: 12),
          // MGRS / UTM placeholder
          Row(
            children: [
              Text(
                'DD  ',
                style: TextStyle(
                  color: Colors.greenAccent.withValues(alpha: 0.5),
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoordRow extends StatelessWidget {
  final String label;
  final String decimal;
  final String dms;

  const _CoordRow({
    required this.label,
    required this.decimal,
    required this.dms,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label ',
          style: TextStyle(
            color: Colors.greenAccent.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        Expanded(
          child: Text(
            dms,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Text(
          decimal,
          style: const TextStyle(
            color: Colors.white30,
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// ── Barra visual de referencia de azimut ──────────────────────────────────────
class _AzimutBar extends StatelessWidget {
  final double heading;
  const _AzimutBar({required this.heading});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(painter: _AzimutBarPainter(heading)),
      ),
    );
  }
}

class _AzimutBarPainter extends CustomPainter {
  final double heading;
  _AzimutBarPainter(this.heading);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Cada pixel = 1 grado
    const degreesPerPixel = 1.0;
    final visibleDeg = w * degreesPerPixel;

    final startDeg = heading - visibleDeg / 2;

    // Ticks
    for (
      double d = startDeg.floor().toDouble();
      d <= startDeg + visibleDeg;
      d++
    ) {
      final normalized = ((d % 360) + 360) % 360;
      final x = cx + (d - heading) / degreesPerPixel;
      final isCard = normalized % 90 == 0;
      final isSub = normalized % 45 == 0;
      final is10 = normalized % 10 == 0;
      if (!is10 && !isCard && !isSub) continue;

      final tickH = isCard
          ? 24.0
          : isSub
          ? 18.0
          : 12.0;
      canvas.drawLine(
        Offset(x, (h - tickH) / 2),
        Offset(x, (h + tickH) / 2),
        Paint()
          ..color = isCard
              ? Colors.greenAccent.withValues(alpha: 0.9)
              : Colors.white24
          ..strokeWidth = isCard ? 1.5 : 1.0,
      );

      // Etiquetas cardinales
      if (isCard) {
        final lbl = _cardinalLabel(normalized);
        if (lbl.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: lbl,
              style: TextStyle(
                color: normalized == 0 || normalized == 360
                    ? Colors.redAccent
                    : Colors.greenAccent,
                fontSize: 8,
                fontFamily: 'monospace',
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x - tp.width / 2, 2));
        }
      }
    }

    // Indicador central (triángulo apuntando abajo)
    final path = Path()
      ..moveTo(cx, h / 2 - 4)
      ..lineTo(cx - 5, h / 2 - 14)
      ..lineTo(cx + 5, h / 2 - 14)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.greenAccent);
  }

  static String _cardinalLabel(double normalized) {
    if (normalized == 0 || normalized == 360) return 'N';
    if (normalized == 90) return 'E';
    if (normalized == 180) return 'S';
    if (normalized == 270) return 'O';
    return '';
  }

  @override
  bool shouldRepaint(_AzimutBarPainter old) => old.heading != heading;
}

// ── Inclinómetro de burbuja — datos reales del acelerómetro ───────────────────
class _BubbleLevelWidget extends StatefulWidget {
  const _BubbleLevelWidget();

  @override
  State<_BubbleLevelWidget> createState() => _BubbleLevelWidgetState();
}

class _BubbleLevelWidgetState extends State<_BubbleLevelWidget> {
  // tilt normalizado ±1 (1g = 9.81 m/s²)
  double _tiltX = 0; // roll  → burbuja horizontal
  double _tiltY = 0; // pitch → ángulo vertical
  StreamSubscription<AccelerometerEvent>? _accelSub;

  @override
  void initState() {
    super.initState();
    _accelSub =
        accelerometerEventStream(
          samplingPeriod: SensorInterval.uiInterval,
        ).listen((event) {
          if (!mounted) return;
          setState(() {
            _tiltX = (event.x / 9.81).clamp(-1.0, 1.0);
            _tiltY = (event.y / 9.81).clamp(-1.0, 1.0);
          });
        });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rollDeg = (_tiltX * 90);
    final pitchDeg = (_tiltY * 90);
    final isLevel = _tiltX.abs() < 0.03 && _tiltY.abs() < 0.03;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLevel
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : Colors.greenAccent.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'ROLL ',
                style: TextStyle(
                  color: Colors.greenAccent.withValues(alpha: 0.5),
                  fontSize: 8,
                  fontFamily: 'monospace',
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 22,
                  child: CustomPaint(
                    painter: _BubblePainter(_tiltX * 0.5),
                    size: const Size(double.infinity, 22),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${rollDeg.toStringAsFixed(1)}°',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isLevel ? Icons.check_circle_outline : Icons.warning_amber,
                color: isLevel ? Colors.greenAccent : Colors.orangeAccent,
                size: 11,
              ),
              const SizedBox(width: 4),
              Text(
                isLevel
                    ? 'NIVELADO'
                    : 'R:${rollDeg.toStringAsFixed(1)}°  P:${pitchDeg.toStringAsFixed(1)}°',
                style: TextStyle(
                  color: isLevel ? Colors.greenAccent : Colors.orangeAccent,
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  final double tilt; // –0.5 a +0.5
  _BubblePainter(this.tilt);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final tubeR = h / 2 - 2;

    // Tubo
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: w - 20, height: h - 4),
        Radius.circular(tubeR),
      ),
      Paint()..color = const Color(0xFF1A2535),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: w - 20, height: h - 4),
        Radius.circular(tubeR),
      ),
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Línea central
    canvas.drawLine(
      Offset(cx, cy - tubeR + 2),
      Offset(cx, cy + tubeR - 2),
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.3)
        ..strokeWidth = 0.5,
    );

    // Burbuja
    final bubbleX = cx + tilt * (w / 2 - 30);
    final bubbleColor = tilt.abs() < 0.05
        ? Colors.greenAccent
        : Colors.orangeAccent;
    canvas.drawCircle(
      Offset(bubbleX, cy),
      tubeR - 2,
      Paint()..color = bubbleColor.withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      Offset(bubbleX, cy),
      tubeR - 2,
      Paint()
        ..color = bubbleColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.tilt != tilt;
}

// ── No sensor ─────────────────────────────────────────────────────────────────
class _NoSensorWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors_off, color: Colors.white24, size: 24),
            const SizedBox(height: 4),
            const Text(
              'Sin sensor\nmagnético',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white30,
                fontSize: 8,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
