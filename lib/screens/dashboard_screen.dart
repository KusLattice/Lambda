import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/models/lat_lng.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/theme_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lambda_app/screens/tips_hacks_screen.dart';
import 'package:lambda_app/widgets/telecom_news_banner.dart';
import 'package:lambda_app/widgets/app_drawer.dart';
import 'package:lambda_app/widgets/compass_module.dart';
import 'package:lambda_app/widgets/draggable_module.dart';
import 'package:lambda_app/widgets/weather_banner.dart';
import 'package:lambda_app/widgets/grid_background.dart';
import 'package:lambda_app/providers/dashboard_providers.dart';
import 'package:lambda_app/widgets/offline_banner.dart';
import 'package:lambda_app/providers/notification_providers.dart';
import 'package:lambda_app/config/modules_config.dart';
import 'package:lambda_app/widgets/search_banner.dart';
import 'package:lambda_app/services/ota_update_service.dart';


class MainDashboard extends ConsumerStatefulWidget {
  static const String routeName = '/dashboard';

  const MainDashboard({super.key});

  @override
  ConsumerState<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends ConsumerState<MainDashboard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initial presence update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).updatePresence();
      _checkFirstLoginMetadata();
      // Check for OTA updates on dashboard load
      OtaUpdateService().checkForUpdates(context);
      // Inicializar timestamp de Random desde SharedPreferences
      initLastSeenRandom(ref.read(lastSeenRandomTimestampProvider.notifier));
    });

    // Update presence every 5 minutes while dashboard is open
    _presenceTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      ref.read(authProvider.notifier).updatePresence();
    });

  }

  Future<void> _checkFirstLoginMetadata() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || user.firstLoginAt != null) return;

    // Solo pedimos permisos si es la primera vez que se loguea
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      final position = await Geolocator.getCurrentPosition();
      ref
          .read(authProvider.notifier)
          .updateFirstLoginMetadata(
            LatLng(position.latitude, position.longitude),
          );
    } catch (e) {
      debugPrint('Error obteniendo ubicación para metadatos: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authProvider.notifier).updatePresence();
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    super.dispose();
  }

  void _showSecretAccessDialog(BuildContext context, User user) {
    if (user.role == UserRole.SuperAdmin ||
        user.role == UserRole.Admin ||
        user.canAccessVaultLambda) {
      Navigator.pushNamed(context, TipsHacksScreen.routeName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Acceso denegado a la bóveda. Contacta a un Admin.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Si hay un error crítico al cargar el perfil (ej. Firestore bloqueado), lo mostramos.
    if (authState.hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Error de Sistema: ${authState.error}',
                style: const TextStyle(
                  color: Colors.red,
                  fontFamily: 'Courier',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => ref.read(authProvider.notifier).signOut(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Cerrar Sesión / Reiniciar'),
              ),
            ],
          ),
        ),
      );
    }

    final user = authState.valueOrNull;

    // Si no hay usuario y no está cargando, retornamos un fallback vacío o dejamos que main.dart nos desmonte.
    if (user == null) {
      if (authState.isLoading) {
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ),
        );
      }
      return const Scaffold(backgroundColor: Colors.black);
    }

    final currentTheme = ref.watch(themeProvider);
    final showFab = ref.watch(themeFabVisibleProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: currentTheme.background,
        appBar: AppBar(
          title: const Text('LAMBDA'),
          centerTitle: true,
          backgroundColor: currentTheme.background,
        ),
      drawer: AppDrawer(
        user: user,
        onShowSecretDialog: _showSecretAccessDialog,
      ),
      floatingActionButton: !showFab
              ? null
              : Padding(
              padding: const EdgeInsets.only(bottom: 24.0), // Elevado para evitar bordes/gestos
              child: FloatingActionButton(
              mini: true,
              tooltip: 'Cambiar tema',
              backgroundColor: currentTheme.accent,
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SafeArea(
                    child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      border: Border(
                        top: BorderSide(color: currentTheme.accent.withValues(alpha: 0.3), width: 1),
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'CONFIGURACIÓN DE ENLACE',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            fontFamily: 'Courier',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 44, // Altura ultra reducida
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: kLambdaThemes.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final t = kLambdaThemes[index];
                              final sel = t.id == currentTheme.id;
                              return GestureDetector(
                                onTap: () {
                                  ref.read(themeProvider.notifier).setTheme(t);
                                  Navigator.pop(context);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    gradient: sel ? LinearGradient(
                                      colors: [
                                        t.accent.withValues(alpha: 0.2),
                                        t.secondaryAccent.withValues(alpha: 0.1),
                                      ],
                                    ) : null,
                                    color: sel ? null : Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel ? t.accent : Colors.white.withValues(alpha: 0.05),
                                      width: sel ? 1.2 : 0.5,
                                    ),
                                    boxShadow: sel ? [
                                      BoxShadow(
                                        color: t.accent.withValues(alpha: 0.1),
                                        blurRadius: 8,
                                        spreadRadius: -2,
                                      )
                                    ] : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(t.emoji, style: const TextStyle(fontSize: 14)),
                                      const SizedBox(width: 8),
                                      Text(
                                        t.name.toUpperCase(),
                                        style: TextStyle(
                                          color: sel ? Colors.white : Colors.white38,
                                          fontSize: 9,
                                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                    ),
                  ),
                );
              },
              child: const Icon(Icons.palette_outlined, size: 20),
            ),
          ),
      body: Column(
        children: [
          const OfflineBanner(),
          // ── Banner de Clima (fijo, parte superior) ─────────────────────
          const WeatherBanner(),
          // ── Banner de Noticias de Telecomunicaciones ───────────────────
          const TelecomNewsBanner(),
          // ── Banner de Búsqueda (Acceso Rápido) ─────────────────────────
          const SearchBanner(),

          // ── Canvas de módulos flotantes ────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                // Fondo simplificado para el tema predeterminado
                Positioned.fill(
                  child: currentTheme.id == 'lambda_black'
                      ? Container(color: currentTheme.background)
                      : Stack(
                          children: [
                            // Imagen de fondo con Parallax o Estática
                            if (currentTheme.backgroundImageAsset != null)
                              Positioned.fill(
                                child: Opacity(
                                  opacity: 0.35,
                                  child: Image.asset(
                                    currentTheme.backgroundImageAsset!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            
                            // Gradiente y Grid (Solo en temas especiales)
                            Positioned.fill(
                              child: GridBackground(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: currentTheme.backgroundGradient == null
                                        ? currentTheme.background.withValues(alpha: 0.7)
                                        : null,
                                    gradient: currentTheme.backgroundGradient != null
                                        ? LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: currentTheme.backgroundGradient!
                                                .map((c) => c.withValues(alpha: 0.8))
                                                .toList(),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),

                // Obtenemos el estado y el notificador del provider
                ...() {
                  final modulePositions = ref.watch(dashboardModulesProvider);
                  final moduleNotifier = ref.read(
                    dashboardModulesProvider.notifier,
                  );

                  return modulePositions.entries.map((entry) {
                    final title = entry.key;
                    final position = entry.value;

                    // Buscar config del módulo en la lista central
                    final matches = kDashboardModules.where(
                      (m) => m.title == title,
                    );
                    if (matches.isEmpty || !matches.first.canAccess(user)) {
                      return const SizedBox.shrink();
                    }
                    final moduleConfig = matches.first;

                    // Brújula: widget especial sin ruta de navegación
                    final Widget child = (moduleConfig.routeName == null)
                        ? const CompassModule()
                        : InkWell(
                          onTap: () {
                            if (moduleConfig.routeName == '/fiber-cut' &&
                                user.role == UserRole.TecnicoInvitado) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Colors.redAccent,
                                  content: Text(
                                    'Acceso restringido: Sólo usuarios verificados.',
                                  ),
                                ),
                              );
                              return;
                            }
                            Navigator.of(context).pushNamed(
                              moduleConfig.routeName!,
                            );
                          },
                          child: Center(
                            child: Icon(
                              moduleConfig.icon,
                              color: moduleConfig.iconColor,
                              size: 44,
                            ),
                          ),
                        );

                    // Badge para Random: puntito rojo si hay posts nuevos
                    final bool showBadge = (title == 'Random')
                        ? (ref.watch(hasNewRandomPostsProvider).valueOrNull ??
                              false)
                        : false;

                    return DraggableModule(
                      title: title,
                      position: position,
                      showBadge: showBadge,
                      onDragEnd: (newPosition) =>
                          moduleNotifier.updatePosition(title, newPosition),
                      child: child,
                    );
                  });
                }(),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
