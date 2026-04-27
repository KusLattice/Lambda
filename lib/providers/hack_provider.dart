import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/secret_hack_model.dart';
import 'package:lambda_app/models/user_model.dart';

class HackNotifier extends StateNotifier<AsyncValue<List<SecretHack>>> {
  HackNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    FirebaseFirestore.instance
        .collection('hacks_vault')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final hacks = snapshot.docs
                .map((doc) => SecretHack.fromFirestore(doc))
                .toList();
            state = AsyncValue.data(hacks);
          },
          onError: (err) {
            state = AsyncValue.error(err, StackTrace.current);
          },
        );
  }

  Future<void> addHack({
    required SecretHack hack,
    List<File> imageFiles = const [],
    File? videoFile,
  }) async {
    final List<String> imageUrls = [];
    final List<String> videoUrls = [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Subir imágenes
    for (int i = 0; i < imageFiles.length; i++) {
      final ref = FirebaseStorage.instance.ref().child(
        'hacks_media/$timestamp/img_$i.jpg',
      );
      await ref.putFile(imageFiles[i]);
      imageUrls.add(await ref.getDownloadURL());
    }

    // Subir video
    if (videoFile != null) {
      final ref = FirebaseStorage.instance.ref().child(
        'hacks_media/$timestamp/video.mp4',
      );
      await ref.putFile(videoFile);
      videoUrls.add(await ref.getDownloadURL());
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
        .collection('hacks_vault')
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Si hay nuevas imágenes, reemplazamos todas (mismo patrón que Nave/Food)
    if (imageFiles != null && imageFiles.isNotEmpty) {
      // Borrar viejas del storage
      for (final url in existingImageUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
      finalImageUrls.clear();

      // Subir nuevas
      for (int i = 0; i < imageFiles.length; i++) {
        final ref = FirebaseStorage.instance.ref().child(
          'hacks_media/$timestamp/img_$i.jpg',
        );
        await ref.putFile(imageFiles[i]);
        finalImageUrls.add(await ref.getDownloadURL());
      }
    }

    // Si hay nuevo video
    if (videoFile != null) {
      // Borrar viejo
      for (final url in existingVideoUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
      finalVideoUrls.clear();

      final ref = FirebaseStorage.instance.ref().child(
        'hacks_media/$timestamp/video.mp4',
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
        .collection('hacks_vault')
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
        .collection('hacks_vault')
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
          .collection('hacks_vault')
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
      throw Exception('No tienes permiso para borrar este dato secreto.');
    }
  }
}

final hacksProvider =
    StateNotifierProvider<HackNotifier, AsyncValue<List<SecretHack>>>((ref) {
      return HackNotifier();
    });
