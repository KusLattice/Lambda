import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/nave_post.dart';

final navePostsProvider = StreamProvider.autoDispose
    .family<List<NavePost>, String>((ref, section) {
      return FirebaseFirestore.instance
          .collection('nave_vault')
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
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final String _collection = 'nave_vault';

  Future<void> addPost({
    required NavePost post,
    required List<File> imageFiles,
    File? videoFile,
  }) async {
    final docRef = _firestore.collection(_collection).doc();
    final List<String> uploadedImages = [];
    final List<String> uploadedVideos = [];

    // Subir imágenes
    for (int i = 0; i < imageFiles.length; i++) {
      final ref = _storage.ref().child('nave_media/${docRef.id}_img_$i.jpg');
      await ref.putFile(imageFiles[i]);
      final url = await ref.getDownloadURL();
      uploadedImages.add(url);
    }

    // Subir video
    if (videoFile != null) {
      final ref = _storage.ref().child('nave_media/${docRef.id}_vid.mp4');
      await ref.putFile(videoFile);
      final url = await ref.getDownloadURL();
      uploadedVideos.add(url);
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
    final allUrls = [...imageUrls, ...videoUrls];
    for (String url in allUrls) {
      try {
        final ref = _storage.refFromURL(url);
        await ref.delete();
      } catch (e) {
        debugPrint('nave_provider: Error eliminando archivo ($url): $e');
      }
    }
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
        // Borrar viejas
        for (final url in finalImageUrls) {
          try {
            await _storage.refFromURL(url).delete();
          } catch (_) {}
        }
        finalImageUrls.clear();

        // Subir nuevas
        for (int i = 0; i < imageFiles.length; i++) {
          final ref = _storage.ref().child(
            'nave_media/${id}_img_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );
          await ref.putFile(imageFiles[i]);
          final url = await ref.getDownloadURL();
          finalImageUrls.add(url);
        }
      }

      // Manejo de video
      if (videoFile != null) {
        // Borrar viejo si existe
        for (final url in finalVideoUrls) {
          try {
            await _storage.refFromURL(url).delete();
          } catch (_) {}
        }
        finalVideoUrls.clear();

        // Subir nuevo
        final ref = _storage.ref().child(
          'nave_media/${id}_vid_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await ref.putFile(videoFile);
        final url = await ref.getDownloadURL();
        finalVideoUrls.add(url);
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
