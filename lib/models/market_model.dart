import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum MarketCategory { Herramientas, Vehiculos, Servicios, Varios }

extension MarketCategoryExtension on MarketCategory {
  String get displayName {
    switch (this) {
      case MarketCategory.Herramientas:
        return 'Herramientas';
      case MarketCategory.Vehiculos:
        return 'Vehículos';
      case MarketCategory.Servicios:
        return 'Servicios';
      case MarketCategory.Varios:
        return 'Varios';
    }
  }
}

@immutable
class MarketItem {
  final String id;
  final String sellerId;
  final String sellerName;
  final String title;
  final String description;
  final double? price;
  final MarketCategory category;
  final List<String> imageUrls;

  /// URLs de videos del ítem. Retrocompatible: vacío si no existe en Firestore.
  final List<String> videoUrls;
  final DateTime createdAt;
  final bool isSold;
  final String? region;

  const MarketItem({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.title,
    required this.description,
    this.price,
    required this.category,
    required this.imageUrls,
    this.videoUrls = const [],
    required this.createdAt,
    this.isSold = false,
    this.region,
  });

  MarketItem copyWith({
    String? id,
    String? sellerId,
    String? sellerName,
    String? title,
    String? description,
    double? price,
    MarketCategory? category,
    List<String>? imageUrls,
    List<String>? videoUrls,
    DateTime? createdAt,
    bool? isSold,
    String? region,
  }) {
    return MarketItem(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      category: category ?? this.category,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      createdAt: createdAt ?? this.createdAt,
      isSold: isSold ?? this.isSold,
      region: region ?? this.region,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sellerId': sellerId,
      'sellerName': sellerName,
      'title': title,
      'description': description,
      'price': price,
      'category': category.name,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'createdAt': Timestamp.fromDate(createdAt),
      'isSold': isSold,
      'region': region,
    };
  }

  factory MarketItem.fromMap(Map<String, dynamic> map, String documentId) {
    return MarketItem(
      id: documentId,
      sellerId: map['sellerId'] ?? '',
      sellerName: map['sellerName'] ?? 'Anónimo',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      price: map['price']?.toDouble(),
      category: MarketCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => MarketCategory.Varios,
      ),
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      videoUrls: List<String>.from(map['videoUrls'] ?? []),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isSold: map['isSold'] ?? false,
      region: map['region'],
    );
  }
}
