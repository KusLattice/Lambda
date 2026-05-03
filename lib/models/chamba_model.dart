import 'package:cloud_firestore/cloud_firestore.dart';

enum ChambaType { busca, ofrece }

class ChambaPost {
  final String id;
  final String title;
  final String description;
  final ChambaType type;
  final String? salary;
  final String? location;
  final String authorId;
  final String authorName;
  final DateTime timestamp;
  final List<String> interestedUserIds;
  final String? imageUrl;

  ChambaPost({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    this.salary,
    this.location,
    required this.authorId,
    required this.authorName,
    required this.timestamp,
    this.interestedUserIds = const [],
    this.imageUrl,
  });

  ChambaPost copyWith({
    String? id,
    String? title,
    String? description,
    ChambaType? type,
    String? salary,
    String? location,
    String? authorId,
    String? authorName,
    DateTime? timestamp,
    List<String>? interestedUserIds,
    String? imageUrl,
  }) {
    return ChambaPost(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      salary: salary ?? this.salary,
      location: location ?? this.location,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      timestamp: timestamp ?? this.timestamp,
      interestedUserIds: interestedUserIds ?? this.interestedUserIds,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  factory ChambaPost.fromMap(Map<String, dynamic> map, String id) {
    return ChambaPost(
      id: id,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      type: ChambaType.values.firstWhere(
        (e) => e.name == (map['type'] ?? 'ofrece'),
        orElse: () => ChambaType.ofrece,
      ),
      salary: map['salary'],
      location: map['location'] ?? 'Remoto / Planta',
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? 'Anónimo',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      interestedUserIds: List<String>.from(map['interestedUserIds'] ?? []),
      imageUrl: map['imageUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'type': type.name,
      'salary': salary,
      'location': location,
      'authorId': authorId,
      'authorName': authorName,
      'timestamp': Timestamp.fromDate(timestamp),
      'interestedUserIds': interestedUserIds,
      'imageUrl': imageUrl,
    };
  }
}
