import 'package:cloud_firestore/cloud_firestore.dart';
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

  Future<void> createChamba({
    required String title,
    required String description,
    required ChambaType type,
    String? salary,
    String? location,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    state = const AsyncValue.loading();
    try {
      final post = ChambaPost(
        id: '',
        title: title,
        description: description,
        type: type,
        salary: salary,
        location: location,
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

  Future<void> updateChamba(ChambaPost chamba) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFirestore.instance
          .collection('chambas')
          .doc(chamba.id)
          .update(chamba.toMap());
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
}

final chambaProvider = StateNotifierProvider<ChambaNotifier, AsyncValue<void>>((
  ref,
) {
  return ChambaNotifier(ref);
});
