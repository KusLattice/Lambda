import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/food_post_model.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/services/storage_upload_service.dart';
import 'package:lambda_app/config/firestore_collections.dart';

class FoodNotifier extends StateNotifier<AsyncValue<List<FoodPost>>> {
  FoodNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  StreamSubscription? _sub;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _init() {
    _sub = _firestore
        .collection(FC.foodTracker)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final posts = snapshot.docs
                .map((doc) => FoodPost.fromFirestore(doc))
                .toList();
            if (mounted) state = AsyncValue.data(posts);
          },
          onError: (err) {
            if (mounted) state = AsyncValue.error(err, StackTrace.current);
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> addFoodPost({
    required FoodPost post,
    required List<File> imageFiles,
    File? videoFile,
  }) async {
    final docRef = _firestore.collection(FC.foodTracker).doc();

    // Subir imágenes
    final imageUrls = await StorageUploadService.uploadImages(imageFiles, 'food_media');

    // Subir video
    final List<String> videoUrls = [];
    if (videoFile != null) {
      final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'food_media');
      if (videoUrl != null) videoUrls.add(videoUrl);
    }

    final finalPost = post.copyWith(
      id: docRef.id,
      imageUrls: imageUrls,
      videoUrls: videoUrls,
    );

    await docRef.set(finalPost.toMap());
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
        await StorageUploadService.deleteUrls(finalImageUrls);
        finalImageUrls.clear();

        // Subir nuevas
        final newUrls = await StorageUploadService.uploadImages(imageFiles, 'food_media');
        finalImageUrls.addAll(newUrls);
      }

      // Manejo de video
      if (videoFile != null) {
        // Borrar viejos
        await StorageUploadService.deleteUrls(finalVideoUrls);
        finalVideoUrls.clear();

        // Subir nuevo
        final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'food_media');
        if (videoUrl != null) finalVideoUrls.add(videoUrl);
      }

      final Map<String, dynamic> updateData = Map.from(data);
      updateData['imageUrls'] = finalImageUrls;
      updateData['videoUrls'] = finalVideoUrls;
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(FC.foodTracker).doc(id).update(updateData);
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
    final doc = await _firestore.collection(FC.foodTracker).doc(id).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final isOwner = data['userId'] == currentUser.id;
    final isAdmin = currentUser.isAdmin;

    if (isOwner || isAdmin) {
      // Borrar de Firestore
      await _firestore.collection(FC.foodTracker).doc(id).delete();

      // Borrar de Storage
      final allMedia = <String>[...(imageUrls ?? []), ...(videoUrls ?? [])];
      await StorageUploadService.deleteUrls(allMedia);
    } else {
      throw Exception('No tienes permiso para borrar esta publicación.');
    }
  }
}

final foodProvider =
    StateNotifierProvider<FoodNotifier, AsyncValue<List<FoodPost>>>((ref) {
      return FoodNotifier();
    });
