import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/lodging_post_model.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/services/storage_upload_service.dart';
import 'package:lambda_app/config/firestore_collections.dart';

class LodgingNotifier extends StateNotifier<AsyncValue<List<LodgingPost>>> {
  LodgingNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  StreamSubscription? _sub;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _init() {
    _sub = FirebaseFirestore.instance
        .collection(FC.lodgingTracker)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final posts = snapshot.docs
                .map((doc) => LodgingPost.fromFirestore(doc))
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

  Future<void> addLodgingPost({
    required LodgingPost post,
    List<File> imageFiles = const [],
    File? videoFile,
  }) async {

    // Subir imágenes
    final imageUrls = await StorageUploadService.uploadImages(imageFiles, 'lodging_media');

    // Subir video
    final List<String> videoUrls = [];
    if (videoFile != null) {
      final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'lodging_media');
      if (videoUrl != null) videoUrls.add(videoUrl);
    }

    final postWithMedia = post.copyWith(
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      createdAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    final docRef = _firestore
        .collection(FC.lodgingTracker)
        .doc();
    batch.set(docRef, postWithMedia.toMap());

    final statsRef = _firestore
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


    if (imageFiles != null && imageFiles.isNotEmpty) {
      await StorageUploadService.deleteUrls(existingImageUrls);
      finalImageUrls.clear();
      final newUrls = await StorageUploadService.uploadImages(imageFiles, 'lodging_media');
      finalImageUrls.addAll(newUrls);
    }

    if (videoFile != null) {
      await StorageUploadService.deleteUrls(existingVideoUrls);
      finalVideoUrls.clear();
      final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'lodging_media');
      if (videoUrl != null) finalVideoUrls.add(videoUrl);
    }

    final updateData = {
      ...data,
      'imageUrls': finalImageUrls,
      'videoUrls': finalVideoUrls,
    };

    await FirebaseFirestore.instance
        .collection(FC.lodgingTracker)
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
        .collection(FC.lodgingTracker)
        .doc(id)
        .get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final isOwner = data['userId'] == currentUser.id;
    final isAdmin = currentUser.isAdmin;

    if (isOwner || isAdmin) {
      // Borrar de Firestore
      await FirebaseFirestore.instance
          .collection(FC.lodgingTracker)
          .doc(id)
          .delete();

      // Borrar de Storage
      await StorageUploadService.deleteUrls([...imageUrls, ...videoUrls]);
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
