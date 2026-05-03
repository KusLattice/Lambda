import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/chamba_model.dart';
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

  Future<String?> _uploadImage(File file) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('chambas')
          .child(fileName);
      
      await storageRef.putFile(file);
      return await storageRef.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

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
        imageUrl = await _uploadImage(imageFile);
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
        final imageUrl = await _uploadImage(newImageFile);
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

  Future<void> deleteChamba(String chambaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('chambas')
          .doc(chambaId)
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
