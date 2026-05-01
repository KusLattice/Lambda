import 'package:flutter/material.dart';
import 'dart:math';
import 'package:lambda_app/services/ota_update_service.dart';
import 'package:lambda_app/screens/la_nave_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/models/user_model.dart';

class AboutPage extends ConsumerStatefulWidget {
  static const String routeName = '/about';
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _floatAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(
      begin: 0,
      end: -15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _glowAnimation = Tween<double>(
      begin: 0.1,
      end: 250, // Nivel Supernova: de 120 a 250
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _hablarConMarciano(BuildContext context) {
    final frases = [
      'No sabí diferenciar el cilantro del perejil?',
      'Matacola LC-FC? Chinos culiaos locos, jajajs',
      'Qué shampoo usas para el crecimiento de la frente?',
      'Cierra la boca! párate derecho! dame la patita! rueda!',
      'Error 420: Nivel de mística bajo',
    ];
    final frase = frases[Random().nextInt(frases.length)];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          frase,
          style: const TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.greenAccent, width: 1),
        ),
      ),
    );
  }

  void _accesoRestringido(BuildContext context, User? user) {
    if (user?.role == UserRole.TecnicoInvitado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Acceso denegado a la bóveda marciana. Contacta a un Admin.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (user?.role == UserRole.SuperAdmin ||
        user?.canAccessVaultMartian == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso Concedido, Bienvenido a La Nave.'),
        ),
      );
      Navigator.pushNamed(context, LaNaveScreen.routeName);
      return;
    }

    TextEditingController passController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'PROTOCOLO DE ACCESO',
          style: TextStyle(color: Colors.greenAccent, fontSize: 14),
        ),
        content: TextField(
          controller: passController,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ingrese clave de nivel 1',
            hintStyle: TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (passController.text == 'lambda2026') {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Acceso Concedido, Seba.')),
                );
                Navigator.pushNamed(context, LaNaveScreen.routeName);
              } else {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Error de autenticación. El marciano te juzga.',
                    ),
                  ),
                );
              }
            },
            child: const Text(
              'VALIDAR',
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.valueOrNull;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Créditos',
          style: TextStyle(color: Colors.greenAccent),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.greenAccent),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // LAMBDA FLOTANTE Y RADIACTIVA
            AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, child) {
                final random = Random();
                // Oscilación de brillo potente
                final flicker = random.nextDouble() * 0.3 + 0.85;
                final glowValue = _glowAnimation.value * flicker;

                // Lógica de Glitch extremadamente rara (1.5% de probabilidad)
                final bool isGlitching = random.nextDouble() > 0.985;
                final double jitterX = isGlitching
                    ? (random.nextDouble() - 0.5) * 6
                    : 0;
                final double jitterY = isGlitching
                    ? (random.nextDouble() - 0.5) * 3
                    : 0;

                // Rayos eléctricos y resplandor Hiper-Intenso
                final List<Shadow> electricShadows = [
                  // Núcleo de fusión absoluto (Blanco radiante)
                  Shadow(color: Colors.white, blurRadius: glowValue * 0.1),
                  // Radiación verde de alta densidad (Quemado)
                  Shadow(
                    color: Colors.greenAccent.withValues(alpha: 1.0),
                    blurRadius: glowValue * 1.5,
                  ),
                ];

                if (isGlitching) {
                  electricShadows.add(
                    Shadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.9),
                      offset: Offset(
                        (random.nextDouble() - 0.5) * 20,
                        (random.nextDouble() - 0.5) * 10,
                      ),
                      blurRadius: 4,
                    ),
                  );
                }

                // Auras expansivas masivas (Inundación total de pantalla)
                electricShadows.addAll([
                  Shadow(
                    color: Colors.greenAccent.withValues(alpha: 0.8),
                    blurRadius: glowValue * 8,
                  ),
                  Shadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.6),
                    blurRadius: glowValue * 20,
                  ),
                  Shadow(
                    color: Colors.greenAccent.withValues(alpha: 0.4),
                    blurRadius: glowValue * 45,
                  ),
                  Shadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                    blurRadius: glowValue * 90, // Proyección masiva
                  ),
                ]);

                return Column(
                  children: [
                    Transform.translate(
                      offset: Offset(jitterX, _floatAnimation.value + jitterY),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Aberración Cromática (Glitch)
                          if (isGlitching) ...[
                            // Capa Roja/Magenta
                            Transform.translate(
                              offset: Offset(jitterX * 1.5, jitterY * 1.5),
                              child: const Text(
                                'λ',
                                style: TextStyle(
                                  fontSize: 90,
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w100,
                                ),
                              ),
                            ),
                            // Capa Cian
                            Transform.translate(
                              offset: Offset(-jitterX * 1.8, -jitterY * 1.8),
                              child: const Text(
                                'λ',
                                style: TextStyle(
                                  fontSize: 90,
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.w100,
                                ),
                              ),
                            ),
                          ],
                          // Símbolo Principal
                          Text(
                            'λ',
                            style: TextStyle(
                              fontSize: 90,
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w100,
                              shadows: electricShadows,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'LAMBDA',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 10,
                        shadows: [
                          Shadow(
                            color: Colors.greenAccent.withValues(alpha: 0.4),
                            blurRadius: glowValue / 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 50),
            const Divider(color: Colors.greenAccent, thickness: 0.5),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  const Text(
                    'Desarrollado por: Seba & Gemini AI',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFE0E0E0),
                      fontSize: 13,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 1),
                  const Text(
                    'Propósito: Gestión en terreno y mística técnica.',
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: TextStyle(
                      color: Color(0xFFE0E0E0),
                      fontSize: 13,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final String rawVersion = snapshot.data?.version ?? '0.0.0';
                final List<String> parts = rawVersion.split('.');
                final String major = parts.isNotEmpty ? parts[0] : '0';
                final String minor = parts.length > 1 ? parts[1] : '0';
                final int patch = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;

                String greek = 'α';
                if (patch == 1) greek = 'β';
                if (patch == 2) greek = 'γ';
                if (patch >= 3) greek = 'λ';

                final String displayVersion = 'v$major.$minor$greek';

                return InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Buscando actualizaciones...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    OtaUpdateService().checkForUpdates(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: const BoxDecoration(
                      // Bordes eliminados por requerimiento
                    ),
                    child: Text(
                      displayVersion,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                );
              },
            ),
            const Spacer(),

            // EL MARCIANO ORIGINAL
            GestureDetector(
              onTap: () => _hablarConMarciano(context),
              onLongPress: () => _accesoRestringido(context, user),
              child: Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.black, // Fondo negro sólido
                ),
                child: Column(
                  children: [
                    const Text('👽 ✌️', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 10),
                    Text(
                      'Parte del ecosistema Lattice',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.3),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Derechos reservados - 2026',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white.withValues(alpha: 0.2),
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
