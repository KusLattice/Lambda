import 'package:flutter/material.dart';
import 'package:lambda_app/models/user_model.dart';

/// Representa un módulo del dashboard con toda su configuración.
/// Agregar un nuevo ícono = agregar una entrada a [kDashboardModules]. Nada más.
class DashboardModule {
  final String title;
  final String featureKey;
  final String displayName;
  final IconData icon;
  final Color iconColor;

  /// Ruta de navegación. Si es null, el módulo usa un widget personalizado (ej. Brújula).
  final String? routeName;

  /// Verificación de rol adicional más allá de blockedFeatures.
  /// Si es null, cualquier usuario con acceso puede verlo.
  final bool Function(User user)? roleCheck;

  const DashboardModule({
    required this.title,
    required this.featureKey,
    required this.displayName,
    required this.icon,
    this.iconColor = Colors.greenAccent,
    this.routeName,
    this.roleCheck,
  });

  /// Retorna true si el usuario puede acceder a este módulo.
  bool canAccess(User user) {
    if (user.blockedFeatures.contains(featureKey)) return false;
    return roleCheck == null || roleCheck!(user);
  }
}
