import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/widgets/grid_background.dart';
import 'package:lambda_app/widgets/user_contributions_list.dart';

/// Pantalla personal de aportes del usuario autenticado.
/// Accesible desde el menú lateral (AppDrawer).
class MisAportesScreen extends ConsumerWidget {
  static const String routeName = '/mis-aportes';

  const MisAportesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: const Center(
          child: Text(
            'No autenticado.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'MIS APORTES',
          style: TextStyle(
            fontFamily: 'Courier',
            color: Colors.tealAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.tealAccent),
      ),
      body: Stack(
        children: [
          const GridBackground(child: SizedBox.expand()),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [UserContributionsList(user: user)],
          ),
        ],
      ),
    );
  }
}
