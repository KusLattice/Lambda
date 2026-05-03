import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/market_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/services/storage_upload_service.dart';
import 'package:lambda_app/config/firestore_collections.dart';

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
      // Subir imágenes
      final imageUrls = await StorageUploadService.uploadImages(imageFiles, 'market_media');

      // Subir video
      final List<String> videoUrls = [];
      if (videoFile != null) {
        final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'market_media');
        if (videoUrl != null) videoUrls.add(videoUrl);
      }

      final itemWithMedia = item.copyWith(
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        createdAt: DateTime.now(),
      );

      await _firestore.collection(FC.marketItems).add(itemWithMedia.toMap());
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
      await _firestore.collection(FC.marketItems).doc(itemId).delete();

      // Borrar de Storage
      await StorageUploadService.deleteUrls([...imageUrls, ...videoUrls]);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> toggleSoldStatus(String itemId, bool isSold) async {
    state = const AsyncValue.loading();
    try {
      await _firestore.collection(FC.marketItems).doc(itemId).update({
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

      if (imageFiles != null && imageFiles.isNotEmpty) {
        await StorageUploadService.deleteUrls(existingImageUrls);
        finalImageUrls.clear();
        final newUrls = await StorageUploadService.uploadImages(imageFiles, 'market_media');
        finalImageUrls.addAll(newUrls);
      }

      if (videoFile != null) {
        await StorageUploadService.deleteUrls(existingVideoUrls);
        finalVideoUrls.clear();
        final videoUrl = await StorageUploadService.uploadVideo(videoFile, 'market_media');
        if (videoUrl != null) finalVideoUrls.add(videoUrl);
      }

      final updateData = {
        ...data,
        'imageUrls': finalImageUrls,
        'videoUrls': finalVideoUrls,
      };

      await _firestore.collection(FC.marketItems).doc(id).update(updateData);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final marketNotifierProvider =
    AutoDisposeAsyncNotifierProvider<MarketNotifier, void>(MarketNotifier.new);
