import 'package:cloud_firestore/cloud_firestore.dart';

class SecretHack {
  final String id;
  final String userId;
  final String authorName;
  final String title;
  final String info;
  final String category;
  final String? location;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final DateTime createdAt;

  SecretHack({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.title,
    required this.info,
    required this.category,
    this.location,
    this.imageUrls = const [],
    this.videoUrls = const [],
    required this.createdAt,
  });

  factory SecretHack.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SecretHack(
      id: doc.id,
      userId: data['userId'] ?? '',
      authorName: data['authorName'] ?? 'Anónimo',
      title: data['title'] ?? '',
      info: data['info'] ?? '',
      category: data['category'] ?? 'Datitos',
      location: data['location'],
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      videoUrls: List<String>.from(data['videoUrls'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'authorName': authorName,
      'title': title,
      'info': info,
      'category': category,
      if (location != null) 'location': location,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
