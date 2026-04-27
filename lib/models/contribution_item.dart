import 'package:flutter/material.dart';

/// Tipos de aporte disponibles en la aplicación Lambda.
/// Cada valor corresponde a una colección de Firestore.
enum ContributionType {
  picaFood,
  hospedaje,
  mercado,
  truco,
  laNave,
  falla,
  chamba,
}

/// Extensión con metadatos visuales y de negocio para cada tipo de aporte.
extension ContributionTypeExtension on ContributionType {
  String get displayName {
    switch (this) {
      case ContributionType.picaFood:
        return 'Picás';
      case ContributionType.hospedaje:
        return 'Hospedaje';
      case ContributionType.mercado:
        return 'Mercado';
      case ContributionType.truco:
        return 'Trucos';
      case ContributionType.laNave:
        return 'La Nave';
      case ContributionType.falla:
        return 'Fallas';
      case ContributionType.chamba:
        return 'Chambas';
    }
  }

  IconData get icon {
    switch (this) {
      case ContributionType.picaFood:
        return Icons.restaurant_menu;
      case ContributionType.hospedaje:
        return Icons.hotel;
      case ContributionType.mercado:
        return Icons.storefront;
      case ContributionType.truco:
        return Icons.tips_and_updates;
      case ContributionType.laNave:
        return Icons.rocket_launch;
      case ContributionType.falla:
        return Icons.cable;
      case ContributionType.chamba:
        return Icons.work_outline;
    }
  }

  Color get color {
    switch (this) {
      case ContributionType.picaFood:
        return Colors.orangeAccent;
      case ContributionType.hospedaje:
        return Colors.blueAccent;
      case ContributionType.mercado:
        return Colors.amberAccent;
      case ContributionType.truco:
        return Colors.greenAccent;
      case ContributionType.laNave:
        return Colors.purpleAccent;
      case ContributionType.falla:
        return Colors.redAccent;
      case ContributionType.chamba:
        return Colors.tealAccent;
    }
  }
}

/// DTO inmutable que unifica aportes de distintas colecciones.
/// Solo contiene los campos necesarios para renderizar la lista.
class ContributionItem {
  final ContributionType type;
  final String title;
  final String subtitle;
  final DateTime createdAt;

  /// ID del documento original en Firestore (para futura navegación al detalle).
  final String sourceId;

  const ContributionItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.sourceId,
  });
}
