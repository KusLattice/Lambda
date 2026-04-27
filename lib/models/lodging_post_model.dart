import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class LodgingPost {
  final String id;
  final String userId;
  final String authorName;
  final String title;
  final String description;
  final String locationName;
  final GeoPoint? coordinates; // Lat/Lng if logged from GPS
  final List<String> imageUrls;

  /// URLs de videos adjuntos al hospedaje. Retrocompatible: vacío si no existe en Firestore.
  final List<String> videoUrls;
  final DateTime createdAt;
  final double? pricePerNight;
  final int rating; // 1 to 5 index representing stars (creator's self-rating)
  final String? region;
  // Campos de rating colectivo (votos de la comunidad)
  final double ratingAverage;
  final int ratingCount;

  const LodgingPost({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.title,
    required this.description,
    required this.locationName,
    this.coordinates,
    required this.imageUrls,
    this.videoUrls = const [],
    required this.createdAt,
    this.pricePerNight,
    this.rating = 0,
    this.region,
    this.ratingAverage = 0.0,
    this.ratingCount = 0,
  });

  LodgingPost copyWith({
    String? id,
    String? userId,
    String? authorName,
    String? title,
    String? description,
    String? locationName,
    GeoPoint? coordinates,
    List<String>? imageUrls,
    List<String>? videoUrls,
    DateTime? createdAt,
    double? pricePerNight,
    int? rating,
    String? region,
    double? ratingAverage,
    int? ratingCount,
  }) {
    return LodgingPost(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      title: title ?? this.title,
      description: description ?? this.description,
      locationName: locationName ?? this.locationName,
      coordinates: coordinates ?? this.coordinates,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      createdAt: createdAt ?? this.createdAt,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      rating: rating ?? this.rating,
      region: region ?? this.region,
      ratingAverage: ratingAverage ?? this.ratingAverage,
      ratingCount: ratingCount ?? this.ratingCount,
    );
  }

  factory LodgingPost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LodgingPost(
      id: doc.id,
      userId: data['userId'] ?? '',
      authorName: data['authorName'] ?? 'Anónimo',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      locationName: data['locationName'] ?? '',
      coordinates: data['coordinates'] as GeoPoint?,
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      videoUrls: List<String>.from(data['videoUrls'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pricePerNight: (data['pricePerNight'] as num?)?.toDouble(),
      rating: data['rating']?.toInt() ?? 0,
      region: data['region'] as String?,
      ratingAverage: (data['ratingAverage'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (data['ratingCount'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'authorName': authorName,
      'title': title,
      'description': description,
      'locationName': locationName,
      'coordinates': coordinates,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'createdAt': FieldValue.serverTimestamp(),
      'pricePerNight': pricePerNight,
      'rating': rating,
      if (region != null) 'region': region,
      // ratingAverage y ratingCount los escribe RatingService, no el cliente
    };
  }
}
