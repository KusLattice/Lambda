import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:lambda_app/models/lat_lng.dart';

@immutable
class FiberCutReport {
  final String id;
  final String reporterId;
  final String reporterNickname;
  final String? reporterFotoUrl;
  final LatLng location;
  final String? address;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final DateTime createdAt;
  final bool isResolved;
  final String? description;
  final String? region;
  final String? comuna;

  const FiberCutReport({
    required this.id,
    required this.reporterId,
    required this.reporterNickname,
    this.reporterFotoUrl,
    required this.location,
    this.address,
    this.imageUrls = const [],
    this.videoUrls = const [],
    required this.createdAt,
    this.isResolved = false,
    this.description,
    this.region,
    this.comuna,
  });

  factory FiberCutReport.fromMap(Map<String, dynamic> map, String id) {
    DateTime safeDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return FiberCutReport(
      id: id,
      reporterId: map['reporterId'] ?? '',
      reporterNickname: map['reporterNickname'] ?? 'Usuario',
      reporterFotoUrl: map['reporterFotoUrl'],
      location:
          (map['location'] != null &&
              map['location'] is Map &&
              map['location']['latitude'] != null &&
              map['location']['longitude'] != null)
          ? LatLng(
              (map['location']['latitude'] as num).toDouble(),
              (map['location']['longitude'] as num).toDouble(),
            )
          : LatLng(0, 0),
      address: map['address'],
      imageUrls: List<String>.from(
        map['imageUrls'] ?? (map['photoUrl'] != null ? [map['photoUrl']] : []),
      ),
      videoUrls: List<String>.from(map['videoUrls'] ?? []),
      createdAt: safeDate(map['createdAt']),
      isResolved: map['isResolved'] ?? false,
      description: map['description'],
      region: map['region'],
      comuna: map['comuna'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reporterId': reporterId,
      'reporterNickname': reporterNickname,
      'reporterFotoUrl': reporterFotoUrl,
      'location': {
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
      'address': address,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'photoUrl': imageUrls.isNotEmpty
          ? imageUrls.first
          : null, // Backwards compatibility
      'createdAt': Timestamp.fromDate(createdAt),
      'isResolved': isResolved,
      'description': description,
      'region': region,
      'comuna': comuna,
    };
  }

  FiberCutReport copyWith({
    String? id,
    String? reporterId,
    String? reporterNickname,
    String? reporterFotoUrl,
    LatLng? location,
    String? address,
    List<String>? imageUrls,
    List<String>? videoUrls,
    DateTime? createdAt,
    bool? isResolved,
    String? description,
    String? region,
    String? comuna,
  }) {
    return FiberCutReport(
      id: id ?? this.id,
      reporterId: reporterId ?? this.reporterId,
      reporterNickname: reporterNickname ?? this.reporterNickname,
      reporterFotoUrl: reporterFotoUrl ?? this.reporterFotoUrl,
      location: location ?? this.location,
      address: address ?? this.address,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      createdAt: createdAt ?? this.createdAt,
      isResolved: isResolved ?? this.isResolved,
      description: description ?? this.description,
      region: region ?? this.region,
      comuna: comuna ?? this.comuna,
    );
  }
}
