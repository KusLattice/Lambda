import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/food_post_model.dart';
import 'package:lambda_app/models/user_model.dart';

class FoodNotifier extends StateNotifier<AsyncValue<List<FoodPost>>> {
  FoodNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  void _init() {
    _firestore
        .collection('food_tracker')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final posts = snapshot.docs
                .map((doc) => FoodPost.fromFirestore(doc))
                .toList();
            state = AsyncValue.data(posts);
          },
          onError: (err) {
            state = AsyncValue.error(err, StackTrace.current);
          },
        );
  }

  Future<void> addFoodPost({
    required FoodPost post,
    required List<File> imageFiles,
    File? videoFile,
  }) async {
    final batch = _firestore.batch();
    final docRef = _firestore.collection('food_tracker').doc();

    final List<String> imageUrls = [];
    final List<String> videoUrls = [];

    // Subir imágenes
    for (int i = 0; i < imageFiles.length; i++) {
      final ref = _storage.ref().child('food_media/${docRef.id}_img_$i.jpg');
      await ref.putFile(imageFiles[i]);
      final url = await ref.getDownloadURL();
      imageUrls.add(url);
    }

    // Subir video
    if (videoFile != null) {
      final ref = _storage.ref().child('food_media/${docRef.id}_vid.mp4');
      await ref.putFile(videoFile);
      final url = await ref.getDownloadURL();
      videoUrls.add(url);
    }

    final finalPost = post.copyWith(
      id: docRef.id,
      imageUrls: imageUrls,
      videoUrls: videoUrls,
    );

    batch.set(docRef, finalPost.toMap());

    final statsRef = _firestore.collection('metadata').doc('app_stats');
    batch.set(statsRef, {
      'foodCount': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> updateFoodPost(
    String id,
    Map<String, dynamic> data, {
    List<File>? imageFiles,
    File? videoFile,
    List<String>? existingImageUrls,
    List<String>? existingVideoUrls,
  }) async {
    try {
      final List<String> finalImageUrls = List.from(existingImageUrls ?? []);
      final List<String> finalVideoUrls = List.from(existingVideoUrls ?? []);

      // Si hay nuevas imágenes, reemplazamos (estilo FiberCut/Nave)
      if (imageFiles != null) {
        // Borrar viejas de Storage
        for (final url in finalImageUrls) {
          try {
            await _storage.refFromURL(url).delete();
          } catch (_) {}
        }
        finalImageUrls.clear();

        // Subir nuevas
        for (int i = 0; i < imageFiles.length; i++) {
          final ref = _storage.ref().child(
            'food_media/${id}_img_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );
          await ref.putFile(imageFiles[i]);
          final url = await ref.getDownloadURL();
          finalImageUrls.add(url);
        }
      }

      // Manejo de video
      if (videoFile != null) {
        // Borrar viejos
        for (final url in finalVideoUrls) {
          try {
            await _storage.refFromURL(url).delete();
          } catch (_) {}
        }
        finalVideoUrls.clear();

        // Subir nuevo
        final ref = _storage.ref().child(
          'food_media/${id}_vid_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await ref.putFile(videoFile);
        final url = await ref.getDownloadURL();
        finalVideoUrls.add(url);
      }

      final Map<String, dynamic> updateData = Map.from(data);
      updateData['imageUrls'] = finalImageUrls;
      updateData['videoUrls'] = finalVideoUrls;
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('food_tracker').doc(id).update(updateData);
    } catch (e) {
      debugPrint('Error updating food post: $e');
      rethrow;
    }
  }

  Future<void> deletePost(
    String id,
    User currentUser, {
    List<String>? imageUrls,
    List<String>? videoUrls,
  }) async {
    final doc = await _firestore.collection('food_tracker').doc(id).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final isOwner = data['userId'] == currentUser.id;
    final isAdmin =
        currentUser.role == UserRole.Admin ||
        currentUser.role == UserRole.SuperAdmin;

    if (isOwner || isAdmin) {
      // Borrar de Firestore
      await _firestore.collection('food_tracker').doc(id).delete();

      // Borrar de Storage
      final allMedia = [...(imageUrls ?? []), ...(videoUrls ?? [])];

      for (final url in allMedia) {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {}
      }
    } else {
      throw Exception('No tienes permiso para borrar esta publicación.');
    }
  }
}

final foodProvider =
    StateNotifierProvider<FoodNotifier, AsyncValue<List<FoodPost>>>((ref) {
      return FoodNotifier();
    });
