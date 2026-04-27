import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/notification_providers.dart';
import 'package:lambda_app/providers/stats_provider.dart';
import 'package:lambda_app/screens/about_screen.dart';
import 'package:lambda_app/screens/admin_panel_screen.dart';
import 'package:lambda_app/screens/profile_screen.dart';
import 'package:lambda_app/screens/mail_screen.dart';
import 'package:lambda_app/screens/mis_aportes_screen.dart';
import 'package:lambda_app/widgets/contact_form_dialog.dart';

class AppDrawer extends ConsumerWidget {
  final User? user;
  final Function(BuildContext, User) onShowSecretDialog;

  const AppDrawer({
    super.key,
    required this.user,
    required this.onShowSecretDialog,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isAdmin =
        user?.role == UserRole.Admin || user?.role == UserRole.SuperAdmin;

    return Drawer(
      backgroundColor: const Color(0xFF111111),
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.black),
            child: Center(
              child: GestureDetector(
                onLongPress: () {
                  if (user != null) onShowSecretDialog(context, user!);
                },
                child: const Text(
                  'λ',
                  style: TextStyle(
                    fontSize: 60,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w100,
                    shadows: [
                      Shadow(
                        color: Colors.greenAccent,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline, color: Colors.white54),
            title: const Text('Usuario', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context); // Cierra el drawer
              Navigator.pushNamed(context, ProfileScreen.routeName);
            },
          ),
          ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.mail_outline, color: Colors.greenAccent),
                if (ref.watch(unreadMailCountProvider).valueOrNull != null &&
                    ref.watch(unreadMailCountProvider).valueOrNull! > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            title: const Text(
              'Correo λ',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, MailScreen.routeName);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.list_alt_rounded,
              color: Colors.tealAccent,
            ),
            title: const Text(
              'Mis Aportes',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, MisAportesScreen.routeName);
            },
          ),
          if (isAdmin)
            ListTile(
              leading: const Icon(Icons.security, color: Colors.cyanAccent),
              title: const Text(
                'Panel de Admin',
                style: TextStyle(color: Colors.cyanAccent),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AdminPanelScreen.routeName);
              },
            ),
          if (isAdmin)
            ListTile(
              leading: const Icon(Icons.bar_chart, color: Colors.amber),
              title: const Text(
                'Estadísticas Globales',
                style: TextStyle(color: Colors.amber),
              ),
              subtitle: ref
                  .watch(statsProvider)
                  .when(
                    data: (stats) => Text(
                      'Colegas: ${stats.activeUsers} | Visitas: ${stats.totalVisits}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    loading: () => const Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    error: (_, _) => const Text(
                      'Error',
                      style: TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/global_stats');
              },
            ),
          ListTile(
            leading: const Icon(Icons.support_agent, color: Colors.greenAccent),
            title: const Text(
              'Contacto / Soporte',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Dudas, sugerencias o reclamos',
              style: TextStyle(color: Colors.white24, fontSize: 10),
            ),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) => const ContactFormDialog(),
              );
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white54),
            title: const Text(
              'Acerca de...',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AboutPage.routeName);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white54),
            title: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () async {
              // Limpiar toda la pila de navegación (incluyendo el drawer) hasta la raíz
              Navigator.of(context).popUntil((route) => route.isFirst);
              // Cerrar sesión desencadena el cambio natural a LoginScreen en main.dart
              await ref.read(authProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );
  }
}
