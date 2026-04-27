import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:lambda_app/models/lat_lng.dart';

enum MediaType { image, video }

@immutable
class NavePost {
  final String id;
  final String authorId;
  final String authorNickname;
  final String? authorFotoUrl;
  final String title;
  final String content;
  final String section; // 'Deja tu cola', 'Manos', 'Foro'
  final List<String> imageUrls;
  final List<String> videoUrls;
  final LatLng? location;
  final String? address;
  final DateTime createdAt;
  final int upvotes;
  final String? region;

  const NavePost({
    required this.id,
    required this.authorId,
    required this.authorNickname,
    this.authorFotoUrl,
    required this.title,
    required this.content,
    required this.section,
    required this.imageUrls,
    required this.videoUrls,
    this.location,
    this.address,
    required this.createdAt,
    this.upvotes = 0,
    this.region,
  });

  factory NavePost.fromMap(Map<String, dynamic> map, String id) {
    DateTime safeDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return NavePost(
      id: id,
      authorId: map['authorId'] ?? '',
      authorNickname: map['authorNickname'] ?? 'Usuario',
      authorFotoUrl: map['authorFotoUrl'],
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      section: map['section'] ?? 'Foro',
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      videoUrls: map['videoUrls'] != null 
          ? List<String>.from(map['videoUrls'])
          : (map['videoUrl'] != null ? [map['videoUrl'] as String] : []),
      location: map['location'] != null
          ? LatLng(
              (map['location']['latitude'] as num).toDouble(),
              (map['location']['longitude'] as num).toDouble(),
            )
          : null,
      address: map['address'],
      createdAt: safeDate(map['createdAt']),
      upvotes: map['upvotes'] ?? 0,
      region: map['region'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'authorNickname': authorNickname,
      'authorFotoUrl': authorFotoUrl,
      'title': title,
      'content': content,
      'section': section,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'location': location != null
          ? {'latitude': location!.latitude, 'longitude': location!.longitude}
          : null,
      'address': address,
      'createdAt': Timestamp.fromDate(createdAt),
      'upvotes': upvotes,
      'region': region,
    };
  }

  NavePost copyWith({
    String? id,
    String? authorId,
    String? authorNickname,
    String? authorFotoUrl,
    String? title,
    String? content,
    String? section,
    List<String>? imageUrls,
    List<String>? videoUrls,
    LatLng? location,
    String? address,
    DateTime? createdAt,
    int? upvotes,
    String? region,
  }) {
    return NavePost(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorNickname: authorNickname ?? this.authorNickname,
      authorFotoUrl: authorFotoUrl ?? this.authorFotoUrl,
      title: title ?? this.title,
      content: content ?? this.content,
      section: section ?? this.section,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      location: location ?? this.location,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      upvotes: upvotes ?? this.upvotes,
      region: region ?? this.region,
    );
  }
}
