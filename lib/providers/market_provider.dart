import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/market_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';

final marketItemsProvider = StreamProvider.autoDispose<List<MarketItem>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('market_items')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => MarketItem.fromMap(doc.data(), doc.id))
            .toList(),
      );
});

class MarketNotifier extends AutoDisposeAsyncNotifier<void> {
  FirebaseFirestore get _firestore => ref.read(firestoreProvider);

  @override
  FutureOr<void> build() {}

  Future<void> addMarketItem({
    required MarketItem item,
    List<File> imageFiles = const [],
    File? videoFile,
  }) async {
    state = const AsyncValue.loading();
    try {
      final List<String> imageUrls = [];
      final List<String> videoUrls = [];
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Subir imágenes
      for (int i = 0; i < imageFiles.length; i++) {
        final ref = FirebaseStorage.instance.ref().child(
          'market_media/$timestamp/img_$i.jpg',
        );
        await ref.putFile(imageFiles[i]);
        imageUrls.add(await ref.getDownloadURL());
      }

      // Subir video
      if (videoFile != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'market_media/$timestamp/video.mp4',
        );
        await ref.putFile(videoFile);
        videoUrls.add(await ref.getDownloadURL());
      }

      final itemWithMedia = item.copyWith(
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        createdAt: DateTime.now(),
      );

      await _firestore.collection('market_items').add(itemWithMedia.toMap());
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> deleteMarketItem(
    String itemId, {
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
  }) async {
    state = const AsyncValue.loading();
    try {
      // Borrar de Firestore
      await _firestore.collection('market_items').doc(itemId).delete();

      // Borrar de Storage
      final allMedia = [...imageUrls, ...videoUrls];
      for (final url in allMedia) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> toggleSoldStatus(String itemId, bool isSold) async {
    state = const AsyncValue.loading();
    try {
      await _firestore.collection('market_items').doc(itemId).update({
        'isSold': isSold,
      });
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> updateMarketItem(
    String id,
    Map<String, dynamic> data, {
    List<File>? imageFiles,
    File? videoFile,
    List<String> existingImageUrls = const [],
    List<String> existingVideoUrls = const [],
  }) async {
    state = const AsyncValue.loading();
    try {
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
            'market_media/$timestamp/img_$i.jpg',
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
          'market_media/$timestamp/video.mp4',
        );
        await ref.putFile(videoFile);
        finalVideoUrls.add(await ref.getDownloadURL());
      }

      final updateData = {
        ...data,
        'imageUrls': finalImageUrls,
        'videoUrls': finalVideoUrls,
      };

      await _firestore.collection('market_items').doc(id).update(updateData);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final marketNotifierProvider =
    AutoDisposeAsyncNotifierProvider<MarketNotifier, void>(MarketNotifier.new);
