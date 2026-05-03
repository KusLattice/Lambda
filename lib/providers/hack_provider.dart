import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/secret_hack_model.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/services/storage_upload_service.dart';
import 'package:lambda_app/config/firestore_collections.dart';
class HackNotifier extends StateNotifier<AsyncValue<List<SecretHack>>> {
  HackNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  StreamSubscription? _sub;

  void _init() {
    _sub = FirebaseFirestore.instance
        .collection(FC.hacksVault)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final hacks = snapshot.docs
                .map((doc) => SecretHack.fromFirestore(doc))
                .toList();
            if (mounted) state = AsyncValue.data(hacks);
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

  Future<void> addHack({
    required SecretHack hack,
    List<File> imageFiles = const [],
    File? videoFile,
  }) async {
    // Subir imágenes
    final imageUrls = await StorageUploadService.uploadImages(imageFiles, 'hacks_media');

    // Subir video
    final List<String> videoUrls = [];
    if (videoFile != null) {
      final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'hacks_media');
      if (videoUrl != null) videoUrls.add(videoUrl);
    }

    final hackWithMedia = SecretHack(
      id: '',
      userId: hack.userId,
      authorName: hack.authorName,
      title: hack.title,
      info: hack.info,
      category: hack.category,
      location: hack.location,
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      createdAt: DateTime.now(),
    );

    await FirebaseFirestore.instance
        .collection(FC.hacksVault)
        .add(hackWithMedia.toMap());
  }

  Future<void> updateHack(
    String id,
    Map<String, dynamic> data, {
    List<File>? imageFiles,
    File? videoFile,
    List<String> existingImageUrls = const [],
    List<String> existingVideoUrls = const [],
  }) async {
    List<String> finalImageUrls = List.from(existingImageUrls);
    List<String> finalVideoUrls = List.from(existingVideoUrls);

    // Si hay nuevas imágenes, reemplazamos todas (mismo patrón que Nave/Food)
    if (imageFiles != null && imageFiles.isNotEmpty) {
      // Borrar viejas del storage
      await StorageUploadService.deleteUrls(existingImageUrls);
      finalImageUrls.clear();

      // Subir nuevas
      final newUrls = await StorageUploadService.uploadImages(imageFiles, 'hacks_media');
      finalImageUrls.addAll(newUrls);
    }

    // Si hay nuevo video
    if (videoFile != null) {
      // Borrar viejo
      await StorageUploadService.deleteUrls(existingVideoUrls);
      finalVideoUrls.clear();

      // Subir nuevo
      final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'hacks_media');
      if (videoUrl != null) finalVideoUrls.add(videoUrl);
    }

    final updateData = {
      ...data,
      'imageUrls': finalImageUrls,
      'videoUrls': finalVideoUrls,
    };

    await FirebaseFirestore.instance
        .collection(FC.hacksVault)
        .doc(id)
        .update(updateData);
  }

  Future<void> deleteHack(
    String id,
    User currentUser, {
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
  }) async {
    final doc = await FirebaseFirestore.instance
        .collection(FC.hacksVault)
        .doc(id)
        .get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final isOwner = data['userId'] == currentUser.id;
    final isAdmin = currentUser.isAdmin;

    if (isOwner || isAdmin) {
      // Borrar de Firestore
      await FirebaseFirestore.instance
          .collection(FC.hacksVault)
          .doc(id)
          .delete();

      // Borrar de Storage
      await StorageUploadService.deleteUrls([...imageUrls, ...videoUrls]);
    } else {
      throw Exception('No tienes permiso para borrar este dato secreto.');
    }
  }
}

final hacksProvider =
    StateNotifierProvider<HackNotifier, AsyncValue<List<SecretHack>>>((ref) {
      return HackNotifier();
    });
