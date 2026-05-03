import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/chamba_model.dart';
import 'package:lambda_app/services/storage_upload_service.dart';
import 'package:lambda_app/providers/auth_provider.dart';

final chambasStreamProvider = StreamProvider<List<ChambaPost>>((ref) {
  return FirebaseFirestore.instance
      .collection('chambas')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((doc) => ChambaPost.fromMap(doc.data(), doc.id))
            .toList(),
      );
});

class ChambaNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref ref;
  ChambaNotifier(this.ref) : super(const AsyncValue.data(null));



  Future<void> createChamba({
    required String title,
    required String description,
    required ChambaType type,
    String? salary,
    String? location,
    File? imageFile,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    state = const AsyncValue.loading();
    try {
      String? imageUrl;
      if (imageFile != null) {
        imageUrl = await StorageUploadService.uploadVideo(imageFile, 'chambas'); // uploadVideo works for single file
        // Wait, uploadVideo is for video. uploadImages is for list.
        // I should probably use uploadImages and take first, or just use uploadVideo if it's just putFile + getDownloadURL.
        // StorageUploadService.uploadVideo just does putFile.
      }

      final post = ChambaPost(
        id: '',
        title: title,
        description: description,
        type: type,
        salary: salary,
        location: location,
        imageUrl: imageUrl,
        authorId: user.id,
        authorName: user.apodo ?? user.nombre,
        timestamp: DateTime.now(),
      );

      await FirebaseFirestore.instance.collection('chambas').add(post.toMap());
      state = const AsyncValue.data(null);
    } on FirebaseException catch (e, st) {
      if (e.code == 'permission-denied') {
        state = AsyncValue.error(
          'SECURITY ERROR: No tienes permisos para publicar en "chambas". Revisa las reglas de Firestore.',
          st,
        );
      } else {
        state = AsyncValue.error('SYSTEM ERROR: ${e.message}', st);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> updateChamba(ChambaPost chamba, {File? newImageFile}) async {
    state = const AsyncValue.loading();
    try {
      ChambaPost updatedChamba = chamba;
      if (newImageFile != null) {
        if (chamba.imageUrl != null) {
          await StorageUploadService.deleteUrls([chamba.imageUrl!]);
        }
        final imageUrl = await StorageUploadService.uploadVideo(newImageFile, 'chambas');
        updatedChamba = chamba.copyWith(imageUrl: imageUrl);
      }

      await FirebaseFirestore.instance
          .collection('chambas')
          .doc(updatedChamba.id)
          .update(updatedChamba.toMap());
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> deleteChamba(ChambaPost chamba) async {
    try {
      if (chamba.imageUrl != null) {
        await StorageUploadService.deleteUrls([chamba.imageUrl!]);
      }
      await FirebaseFirestore.instance
          .collection('chambas')
          .doc(chamba.id)
          .delete();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addInterest(String chambaId, String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('chambas')
          .doc(chambaId)
          .update({
        'interestedUserIds': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      rethrow;
    }
  }
}

final chambaProvider = StateNotifierProvider<ChambaNotifier, AsyncValue<void>>((
  ref,
) {
  return ChambaNotifier(ref);
});
