import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/lodging_post_model.dart';
import 'package:lambda_app/models/user_model.dart';

class LodgingNotifier extends StateNotifier<AsyncValue<List<LodgingPost>>> {
  LodgingNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    FirebaseFirestore.instance
        .collection('lodging_tracker')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final posts = snapshot.docs
                .map((doc) => LodgingPost.fromFirestore(doc))
                .toList();
            state = AsyncValue.data(posts);
          },
          onError: (err) {
            state = AsyncValue.error(err, StackTrace.current);
          },
        );
  }

  Future<void> addLodgingPost({
    required LodgingPost post,
    List<File> imageFiles = const [],
    File? videoFile,
  }) async {
    final List<String> imageUrls = [];
    final List<String> videoUrls = [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Subir imágenes
    for (int i = 0; i < imageFiles.length; i++) {
      final ref = FirebaseStorage.instance.ref().child(
        'lodging_media/$timestamp/img_$i.jpg',
      );
      await ref.putFile(imageFiles[i]);
      imageUrls.add(await ref.getDownloadURL());
    }

    // Subir video
    if (videoFile != null) {
      final ref = FirebaseStorage.instance.ref().child(
        'lodging_media/$timestamp/video.mp4',
      );
      await ref.putFile(videoFile);
      videoUrls.add(await ref.getDownloadURL());
    }

    final postWithMedia = post.copyWith(
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      createdAt: DateTime.now(),
    );

    final batch = FirebaseFirestore.instance.batch();
    final docRef = FirebaseFirestore.instance
        .collection('lodging_tracker')
        .doc();
    batch.set(docRef, postWithMedia.toMap());

    final statsRef = FirebaseFirestore.instance
        .collection('metadata')
        .doc('app_stats');
    batch.set(statsRef, {
      'lodgingCount': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> updateLodgingPost(
    String id,
    Map<String, dynamic> data, {
    List<File>? imageFiles,
    File? videoFile,
    List<String> existingImageUrls = const [],
    List<String> existingVideoUrls = const [],
  }) async {
    List<String> finalImageUrls = List.from(existingImageUrls);
    List<String> finalVideoUrls = List.from(existingVideoUrls);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (imageFiles != null && imageFiles.isNotEmpty) {
      for (final url in existingImageUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
      finalImageUrls.clear();
      for (int i = 0; i < imageFiles.length; i++) {
        final ref = FirebaseStorage.instance.ref().child(
          'lodging_media/$timestamp/img_$i.jpg',
        );
        await ref.putFile(imageFiles[i]);
        finalImageUrls.add(await ref.getDownloadURL());
      }
    }

    if (videoFile != null) {
      for (final url in existingVideoUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
      finalVideoUrls.clear();
      final ref = FirebaseStorage.instance.ref().child(
        'lodging_media/$timestamp/video.mp4',
      );
      await ref.putFile(videoFile);
      finalVideoUrls.add(await ref.getDownloadURL());
    }

    final updateData = {
      ...data,
      'imageUrls': finalImageUrls,
      'videoUrls': finalVideoUrls,
    };

    await FirebaseFirestore.instance
        .collection('lodging_tracker')
        .doc(id)
        .update(updateData);
  }

  Future<void> deletePost(
    String id,
    User currentUser, {
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
  }) async {
    final doc = await FirebaseFirestore.instance
        .collection('lodging_tracker')
        .doc(id)
        .get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final isOwner = data['userId'] == currentUser.id;
    final isAdmin =
        currentUser.role == UserRole.Admin ||
        currentUser.role == UserRole.SuperAdmin;

    if (isOwner || isAdmin) {
      // Borrar de Firestore
      await FirebaseFirestore.instance
          .collection('lodging_tracker')
          .doc(id)
          .delete();

      // Borrar de Storage
      final allMedia = [...imageUrls, ...videoUrls];
      for (final url in allMedia) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
    } else {
      throw Exception('No tienes permiso para borrar esta publicación.');
    }
  }
}

final lodgingProvider =
    StateNotifierProvider<LodgingNotifier, AsyncValue<List<LodgingPost>>>((
      ref,
    ) {
      return LodgingNotifier();
    });
