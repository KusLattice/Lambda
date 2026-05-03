import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/nave_post.dart';
import 'package:lambda_app/services/storage_upload_service.dart';
import 'package:lambda_app/config/firestore_collections.dart';

final navePostsProvider = StreamProvider.autoDispose
    .family<List<NavePost>, String>((ref, section) {
      return FirebaseFirestore.instance
          .collection(FC.naveVault)
          .where('section', isEqualTo: section)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => NavePost.fromMap(doc.data(), doc.id))
                .toList();
          });
    });

final naveProvider = Provider<NaveService>((ref) => NaveService());

class NaveService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = FC.naveVault;

  Future<void> addPost({
    required NavePost post,
    required List<File> imageFiles,
    File? videoFile,
  }) async {
    final docRef = _firestore.collection(_collection).doc();
    // Subir imágenes
    final uploadedImages = await StorageUploadService.uploadImages(imageFiles, 'nave_media');

    // Subir video
    final List<String> uploadedVideos = [];
    if (videoFile != null) {
      final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'nave_media');
      if (videoUrl != null) uploadedVideos.add(videoUrl);
    }

    final newPost = post.copyWith(
      id: docRef.id,
      imageUrls: uploadedImages,
      videoUrls: uploadedVideos,
    );
    await docRef.set(newPost.toMap());
  }

  Future<void> deletePost(
    String id,
    List<String> imageUrls,
    List<String> videoUrls,
  ) async {
    await StorageUploadService.deleteUrls([...imageUrls, ...videoUrls]);
    await _firestore.collection(_collection).doc(id).delete();
  }

  Future<void> updatePost(
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

      // Si hay nuevas imágenes, las subimos (y podríamos limpiar las viejas si quisiéramos modo reemplazo completo,
      // pero por ahora para no complicar la UI de edición, asumimos reemplazo o las que vengan nuevas).
      // NOTA: Para ser consistentes con FiberCut, si imageFiles no es null, reemplazamos.
      if (imageFiles != null) {
        await StorageUploadService.deleteUrls(finalImageUrls);
        finalImageUrls.clear();
        final newUrls = await StorageUploadService.uploadImages(imageFiles, 'nave_media');
        finalImageUrls.addAll(newUrls);
      }

      // Manejo de video
      if (videoFile != null) {
        await StorageUploadService.deleteUrls(finalVideoUrls);
        finalVideoUrls.clear();
        final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'nave_media');
        if (videoUrl != null) finalVideoUrls.add(videoUrl);
      }

      final Map<String, dynamic> updateData = Map.from(data);
      updateData['imageUrls'] = finalImageUrls;
      updateData['videoUrls'] = finalVideoUrls;
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(id).update(updateData);
    } catch (e) {
      debugPrint('Error updating post: $e');
      rethrow;
    }
  }
}
