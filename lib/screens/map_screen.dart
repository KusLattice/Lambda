import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lambda_app/config/app_config.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/screens/public_profile_screen.dart';
import 'package:lambda_app/services/geocoding_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:lambda_app/models/lat_lng.dart' as local_coords;
import 'package:lambda_app/providers/fiber_cut_provider.dart';
import 'package:lambda_app/models/fiber_cut_report.dart';
import 'package:lambda_app/screens/fiber_cut_screen.dart';

// webview_windows solo existe en Windows, importar condicionalmente
// ignore: uri_does_not_exist
import 'package:webview_windows/webview_windows.dart'
    if (dart.library.html) 'package:lambda_app/stubs/webview_stub.dart'
    if (dart.library.io) 'package:lambda_app/stubs/webview_stub.dart';

class MapScreen extends ConsumerStatefulWidget {
  static const String routeName = '/map';
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  WebviewController? _webviewController;
  GoogleMapController? _googleMapController;

  final _textController = TextEditingController();
  bool _isWindows = false;
  bool _isSearching = false;
  bool _webViewInitialized = false;
  late final GeocodingService _geocoding = GeocodingService(
    apiKey: AppConfig.mapsApiKey,
  );

  Set<Marker> _markers = {};
  List<User> _mapUsers = [];
  List<FiberCutReport> _mapFiberCuts = [];
  bool _showFiberCuts = true;
  UserRole? _filterRole;
  final Map<String, BitmapDescriptor> _customIcons = {};
  StreamSubscription? _usersSubscription;
  StreamSubscription? _fiberCutsSubscription;

  /// Animation variables para movimiento suave
  Map<String, LatLng> _previousPositions = {};
  AnimationController? _movementController;

  /// Subscription para el stream de posición GPS en tiempo real
  StreamSubscription<Position>? _positionSubscription;

  Timer? _animationTimer;
  final int _animationFrame = 0;
  final Map<String, BitmapDescriptor> _animatedIcons = {};

  @override
  void initState() {
    super.initState();
    _movementController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(() {
        if (mounted) _rebuildMarkers();
      });

    _isWindows = !kIsWeb && Platform.isWindows;
    if (_isWindows) {
      _webviewController = WebviewController();
      initWebviewState();
    }
    if (!_isWindows) {
      _startAnimationTimer();
    }
    _loadCustomIcons();
    _listenToUsers();

    // Arrancar tracking de posición si el usuario ya estaba visible al abrir el mapa
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).valueOrNull;
      if (user?.isVisibleOnMap == true) {
        _startPositionTracking();
      }

      // 🎯 Centrar el mapa si se pasan coordenadas por argumentos
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is local_coords.LatLng && _googleMapController != null) {
        try {
          _googleMapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(args.latitude, args.longitude),
              15,
            ),
          );
        } catch (e) {
          debugPrint('Error animating camera: $e');
        }
      }
    });
  }

  local_coords.LatLng? get _initialCoords {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is local_coords.LatLng) return args;
    return null;
  }

  // ---------------------------------------------------------------------------
  // ANIMACIÓN DE ÍCONOS
  // ---------------------------------------------------------------------------

  void _startAnimationTimer() {
    // Disabled timer to prevent heavy Canvas-to-PNG encoding every 800ms on the main thread,
    // which caused the UI to freeze and crash the app on Android/iOS.
    // Instead, we just render the first frame once to show the icons static.
    if (!mounted) return;
    _updateAnimatedIcons();
  }

  Future<void> _updateAnimatedIcons() async {
    try {
      if (mounted) {
        _animatedIcons['antenna'] = await _createAnimatedMarkerIcon(
          isAntenna: true,
          frame: _animationFrame,
        );

        if (mounted) {
          setState(() {
            _rebuildMarkers();
          });
        }
      }
    } catch (e) {
      debugPrint('Animation frame error: $e');
    }
  }

  Future<void> _loadCustomIcons() async {
    final iconNames = [
      '1', '2', '3', '4', '5', '6', '7', '8',
      'martian1', 'martian2', 'tribal1', 'tribal2'
    ];

    for (final name in iconNames) {
      try {
        final Uint8List markerIcon = await _getBytesFromAsset(
          'assets/icon/map/$name.png',
          60,
        );
        _customIcons[name] = BitmapDescriptor.bytes(markerIcon);
      } catch (e) {
        debugPrint('Error loading icon $name: $e');
      }
    }
    if (mounted) {
      setState(() {
        _rebuildMarkers();
      });
    }
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    final ByteData data = await DefaultAssetBundle.of(context).load(path);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ByteData? byteData = await fi.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  /// Dibuja el OVNI con más detalle y mística cyberpunk-Lambda.
  /// Canvas de 80x80 (más pequeño que el anterior de 120x120).
  Future<BitmapDescriptor> _createAnimatedMarkerIcon({
    bool isAntenna = true,
    required int frame,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Tamaño reducido: 60x60 (antes 80x80)
    const double size = 60;
    const Offset center = Offset(size / 2, size / 2);

    if (isAntenna) {
      // -----------------------------------------------------------------------
      // CORTE REAL / RAYO ELÉCTRICO NEÓN ⚡
      // -----------------------------------------------------------------------
      final redNeon = Colors.redAccent;
      final amberDark = Colors.amberAccent;

      // 1. Glow periférico (halo rojo)
      final glowPaint = Paint()
        ..color = redNeon.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, 22, glowPaint);

      // 2. Fondo del pin (círculo oscuro táctico)
      final bgPaint = Paint()..color = const Color(0xFF151515);
      canvas.drawCircle(center, 18, bgPaint);

      // 3. Borde del pin (rojo intenso)
      final borderPaint = Paint()
        ..color = redNeon
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, 18, borderPaint);

      // 4. Rayo interior ⚡ (Amber + Borde Rojo)
      final boltPaint = Paint()
        ..color = amberDark
        ..style = PaintingStyle.fill;
      final boltPath = Path();
      boltPath.moveTo(size / 2 - 2, 17);
      boltPath.lineTo(size / 2 + 8, 17);
      boltPath.lineTo(size / 2 + 2, 28);
      boltPath.lineTo(size / 2 + 10, 28);
      boltPath.lineTo(size / 2 - 6, 42); // punta fina hacia abajo
      boltPath.lineTo(size / 2 - 2, 32);
      boltPath.lineTo(size / 2 - 10, 32);
      boltPath.close();
      canvas.drawPath(boltPath, boltPaint);

      final boltBorderPaint = Paint()
        ..color = redNeon
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(boltPath, boltBorderPaint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return BitmapDescriptor.defaultMarker;
    return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE — LISTENERS DE USUARIOS Y CORTES 📡
  // ---------------------------------------------------------------------------

  void _listenToUsers() {
    _usersSubscription = FirebaseFirestore.instance
        .collection('users')
        .where('isVisibleOnMap', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          
          _previousPositions = {
            for (final u in _mapUsers)
              if (u.lastKnownPosition != null)
                u.id: LatLng(u.lastKnownPosition!.latitude, u.lastKnownPosition!.longitude)
          };

          _mapUsers = snapshot.docs
              .map((doc) => User.fromMap(doc.data(), doc.id))
              .toList();
          
          _movementController?.forward(from: 0.0);
        });
  }


  void _rebuildMarkers() {
    if (!mounted) return;

    try {
      final newMarkers = <Marker>{};

      // 1. Agregar Usuarios (SOLO si no es Usuario Invitado)
      final currentUser = ref.read(authProvider).valueOrNull;
      final isGuest = currentUser?.role == UserRole.TecnicoInvitado;

      if (!isGuest) {
        for (final user in _mapUsers) {
          // Filtrado táctico de roles (Solo administradores verán el botón, pero la lógica aplica aquí)
          if (_filterRole != null && user.role != _filterRole) continue;

          if (user.lastKnownPosition == null) continue;

          LatLng targetPos = LatLng(
            user.lastKnownPosition!.latitude,
            user.lastKnownPosition!.longitude,
          );
          
          LatLng oldPos = _previousPositions[user.id] ?? targetPos;
          
          double t = _movementController?.value ?? 1.0;
          double currentLat = ui.lerpDouble(oldPos.latitude, targetPos.latitude, t) ?? targetPos.latitude;
          double currentLng = ui.lerpDouble(oldPos.longitude, targetPos.longitude, t) ?? targetPos.longitude;
          
          LatLng animatedPos = LatLng(currentLat, currentLng);

        BitmapDescriptor icon = BitmapDescriptor.defaultMarker;

        // Prioridad 1: Icono de Representante personalizado
        if (user.representativeIcon != null &&
            _customIcons.containsKey(user.representativeIcon) &&
            _customIcons[user.representativeIcon] != null) {
          icon = _customIcons[user.representativeIcon]!;
        } else {
          // Fallback por defecto si no tiene icono seleccionado
          icon = BitmapDescriptor.defaultMarkerWithHue(
            user.canAccessVaultMartian || user.canAccessVaultLambda
                ? BitmapDescriptor.hueGreen
                : BitmapDescriptor.hueRed,
          );
        }

        newMarkers.add(
          Marker(
            markerId: MarkerId('user_${user.id}'),
            position: animatedPos,
            icon: icon,
            onTap: () => _showUserOptions(user),
          ),
        );
      }
    }

      // 2. Agregar Fibras Cortadas (Fallas) 📡
      if (_showFiberCuts) {
        for (final cut in _mapFiberCuts) {
          newMarkers.add(
            Marker(
              markerId: MarkerId('cut_${cut.id}'),
              position: LatLng(cut.location.latitude, cut.location.longitude),
              icon:
                  _animatedIcons['antenna'] ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
              infoWindow: InfoWindow(
                title: '📡 FIBRA CORTADA',
                snippet: '${cut.comuna ?? "SC"}: ${cut.address ?? "Ubicación"}',
                onTap: () =>
                    Navigator.pushNamed(context, FiberCutScreen.routeName),
              ),
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _markers = newMarkers;
        });
      }
    } catch (e) {
      debugPrint('Error rebuilding markers: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // TRACKING DE POSICIÓN EN TIEMPO REAL 📡
  // ---------------------------------------------------------------------------

  Future<void> _startPositionTracking() async {
    try {
      if (_isWindows) return;
      _positionSubscription?.cancel();

      // Check permissions before listening to the stream to prevent crash
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
            ),
          ).listen((Position pos) async {
            if (!mounted) return;
            final user = ref.read(authProvider).valueOrNull;
            if (user?.isVisibleOnMap != true) {
              _stopPositionTracking();
              return;
            }
            await ref
                .read(authProvider.notifier)
                .updateProfileSettings(
                  lastKnownPosition: local_coords.LatLng(
                    pos.latitude,
                    pos.longitude,
                  ),
                );
          }, onError: (e) => debugPrint('Position stream error: $e'));
    } catch (e) {
      debugPrint('Error starting position tracking: $e');
    }
  }

  void _stopPositionTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  @override
  void dispose() {
    _movementController?.dispose();
    _animationTimer?.cancel();
    _usersSubscription?.cancel();
    _fiberCutsSubscription?.cancel();
    _positionSubscription?.cancel();
    _googleMapController?.dispose();
    _textController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // WINDOWS WEBVIEW
  // ---------------------------------------------------------------------------

  Future<void> initWebviewState() async {
    try {
      await _webviewController!.initialize();
      _webviewController!.url.listen((url) {
        if (mounted) _textController.text = url;
      });
      final initialUrl =
          'https://www.google.com/maps/embed/v1/view?key=${AppConfig.mapsApiKey}&center=-33.4489,-70.6693&zoom=5';
      await _webviewController!.loadUrl(initialUrl);
      if (!mounted) return;
      setState(() {
        _webViewInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing webview_windows: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar mapa Windows: $e')),
        );
      }
    }
  }

  Future<void> _searchNativeMap(String address) async {
    if (address.trim().isEmpty) return;
    if (_googleMapController == null) return;
    setState(() => _isSearching = true);
    try {
      final result = await _geocoding.geocode(address);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('No encontrada'),
          ),
        );
        return;
      }
      await _googleMapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(result.lat, result.lng), 14),
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.value;

    // Escuchar reportes de fibra cortada de forma reactiva (vía Riverpod 2.x)
    ref.listen<AsyncValue<List<FiberCutReport>>>(
      activeFiberCutReportsProvider,
      (previous, next) {
        next.whenData((reports) {
          if (!mounted) return;
          setState(() {
            _mapFiberCuts = reports;
            _rebuildMarkers();
          });
        });
      },
    );

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isGuest = user.role == UserRole.TecnicoInvitado;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.amber,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchField(),
              Expanded(child: _buildMap(user)),
            ],
          ),
          Positioned(
            bottom: 100,
            left: 20,
            child: Column(
              children: [
                // 🗡️ Botón de Filtro de Fibras Cortadas
                FloatingActionButton(
                  heroTag: 'filter_fiber',
                  mini: true,
                  backgroundColor: _showFiberCuts
                      ? Colors.redAccent
                      : Colors.grey[900],
                  child: Icon(
                    _showFiberCuts ? Icons.link_off : Icons.link,
                    color: _showFiberCuts ? Colors.black : Colors.white24,
                  ),
                  onPressed: () {
                    setState(() {
                      _showFiberCuts = !_showFiberCuts;
                      _rebuildMarkers();
                    });
                  },
                ),
                if (!isGuest) ...[
                  const SizedBox(height: 10),
                  // 🛸 Botón de Visibilidad de Usuario
                  FloatingActionButton(
                    heroTag: 'map_visibility',
                    mini: true,
                    backgroundColor: user.isVisibleOnMap == true
                        ? Colors.greenAccent
                        : Colors.grey[800],
                    child: Icon(
                      user.isVisibleOnMap == true
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.black,
                    ),
                    onPressed: () => _toggleVisibility(user),
                  ),
                  const SizedBox(height: 10),
                  // 🕶️ Filtro de Roles (Solo Admins)
                  if (user.role == UserRole.Admin || user.role == UserRole.SuperAdmin)
                    PopupMenuButton<UserRole?>(
                      tooltip: 'Filtrar por Segmento',
                      color: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Colors.amber, width: 1),
                      ),
                      onSelected: (role) {
                        setState(() {
                          _filterRole = role;
                          _rebuildMarkers();
                        });
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: null,
                          child: Text('Todos los Segmentos', style: TextStyle(color: Colors.amber)),
                        ),
                        const PopupMenuDivider(height: 1),
                        ...UserRole.values.map(
                          (r) => PopupMenuItem(
                            value: r,
                            child: Text(r.displayName, style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _filterRole == null ? Colors.grey[900] : Colors.amber,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _filterRole == null ? Icons.filter_alt_off : Icons.filter_alt,
                          color: _filterRole == null ? Colors.white54 : Colors.black,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showUserOptions(User user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          border: Border(top: BorderSide(color: Colors.amber, width: 2)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user.apodo ?? user.nombre,
              style: const TextStyle(
                color: Colors.amber,
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              user.role.displayName,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 25),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.cyanAccent),
              title: const Text(
                'VER PERFIL',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  PublicProfileScreen.routeName,
                  arguments: user.id,
                );
              },
            ),
            if (ref.read(authProvider).valueOrNull?.id == user.id ||
                ref.read(authProvider).valueOrNull?.role ==
                    UserRole.SuperAdmin) ...[
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.face, color: Colors.greenAccent),
                title: const Text(
                  'CAMBIAR REPRESENTANTE',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showRepresentativeSelector(user);
                },
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showRepresentativeSelector(User user) {
    // Solo permitir cambiar el propio o si es Admin
    final currentUser = ref.read(authProvider).valueOrNull;
    if (currentUser?.id != user.id &&
        currentUser?.role != UserRole.SuperAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin permisos para cambiar este representante'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'SELECCIONAR REPRESENTANTE',
          style: TextStyle(
            color: Colors.amber,
            fontFamily: 'Courier',
            fontSize: 16,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            shrinkWrap: true,
            children: [
              _buildIconOption(
                context,
                user,
                'default',
                fallbackIcon: Icons.person_pin_circle,
              ),
              if (user.canAccessVaultLambda || user.canAccessVaultMartian) ...[
                _buildIconOption(context, user, 'martian1'),
                _buildIconOption(context, user, 'martian2'),
                _buildIconOption(context, user, 'tribal1'),
                _buildIconOption(context, user, 'tribal2'),
                _buildIconOption(context, user, '1'),
                _buildIconOption(context, user, '2'),
                _buildIconOption(context, user, '3'),
                _buildIconOption(context, user, '4'),
                _buildIconOption(context, user, '5'),
                _buildIconOption(context, user, '6'),
                _buildIconOption(context, user, '7'),
                _buildIconOption(context, user, '8'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconOption(
    BuildContext context,
    User user,
    String iconKey, {
    IconData? fallbackIcon,
  }) {
    final isSelected = user.representativeIcon == iconKey;
    final isAsset = iconKey != 'default';

    return GestureDetector(
      onTap: () async {
        final currentContext = context;
        await ref
            .read(authProvider.notifier)
            .updateProfileSettings(representativeIcon: iconKey);
        if (!currentContext.mounted) return;
        Navigator.pop(currentContext);
        _rebuildMarkers(); // Forzar refresco visual
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.amber.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white12,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(4),
        child: isAsset
            ? Image.asset(
                'assets/icon/map/$iconKey.png',
                width: 40,
                height: 40,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.help_outline, color: Colors.white24, size: 30),
              )
            : Icon(fallbackIcon ?? Icons.person, color: Colors.white, size: 30),
      ),
    );
  }

  Future<void> _toggleVisibility(User? user) async {
    final isCurrentlyVisible = user?.isVisibleOnMap ?? false;
    try {
      if (_isWindows) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GPS no soportado en Windows.')),
          );
        }
        return;
      }

      if (!isCurrentlyVisible) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Activa el GPS primero.')),
            );
          }
          return;
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permisos de GPS denegados.')),
            );
          }
          return;
        }

        final pos = await Geolocator.getCurrentPosition();
        await ref
            .read(authProvider.notifier)
            .updateProfileSettings(
              isVisibleOnMap: true,
              lastKnownPosition: local_coords.LatLng(
                pos.latitude,
                pos.longitude,
              ),
            );
        _startPositionTracking();
      } else {
        _stopPositionTracking();
        await ref
            .read(authProvider.notifier)
            .updateProfileSettings(isVisibleOnMap: false);
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Widget _buildMap(User? currentUser) {
    if (_isWindows && _webviewController != null) {
      return Card(
        child: _webViewInitialized
            ? Webview(_webviewController!)
            : const Center(child: CircularProgressIndicator()),
      );
    } else {
      final initialCoords = _initialCoords;
      return GoogleMap(
        mapType: MapType.hybrid,
        initialCameraPosition: CameraPosition(
          target: initialCoords != null
              ? LatLng(initialCoords.latitude, initialCoords.longitude)
              : const LatLng(-33.4489, -70.6693),
          zoom: initialCoords != null ? 15.0 : 11.0,
        ),
        markers: _markers,
        onMapCreated: (c) {
          _googleMapController = c;
          if (initialCoords != null) {
            // Un pequeño re-centrado extra por si acaso, aunque ya arranca ahí
            c.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(initialCoords.latitude, initialCoords.longitude),
                16.0,
              ),
            );
          }
        },
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
      );
    }
  }

  Widget _buildSearchField() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _textController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Buscar dirección...',
          hintStyle: const TextStyle(color: Colors.white54),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.only(left: 15, top: 15),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_textController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white38,
                    size: 16,
                  ),
                  onPressed: () {
                    _textController.clear();
                    setState(() {});
                  },
                ),
              IconButton(
                icon: _isSearching
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.greenAccent,
                        ),
                      )
                    : const Icon(Icons.search, color: Colors.greenAccent),
                onPressed: _isSearching
                    ? null
                    : () => _searchNativeMap(_textController.text),
              ),
            ],
          ),
        ),
        onSubmitted: (value) => _searchNativeMap(value),
      ),
    );
  }
}
