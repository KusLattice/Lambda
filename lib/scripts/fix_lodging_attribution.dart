import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

// Este script debe ser ejecutado manualmente o llamado por una función administrativa.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final firestore = FirebaseFirestore.instance;

  print('--- PROTOCOLO DE ATRIBUCIÓN INICIADO ---');

  // 1. Buscar a Jorge
  final jorgeSnap = await firestore
      .collection('users')
      .where('email', isEqualTo: 'salgadoespina2@gmail.com')
      .get();

  if (jorgeSnap.docs.isEmpty) {
    print('ERROR: Jorge no encontrado en la base de datos.');
    return;
  }

  final jorgeData = jorgeSnap.docs.first;
  final jorgeId = jorgeData.id;
  final jorgeNombre = jorgeData.data()['nombre'] ?? 'Jorge';

  // 2. Buscar el post de Calama
  final lodgingSnap = await firestore.collection('lodging_tracker').get();
  String? postId;

  for (var doc in lodgingSnap.docs) {
    final data = doc.data();
    final text =
        '${data['title']} ${data['description']} ${data['locationName']}'
            .toLowerCase();
    if (text.contains('calama')) {
      postId = doc.id;
      break;
    }
  }

  if (postId != null) {
    await firestore.collection('lodging_tracker').doc(postId).update({
      'userId': jorgeId,
      'authorName': jorgeNombre,
    });
    print('ÉXITO: Post $postId atribuido a Jorge ($jorgeId).');
  } else {
    print('ERROR: No se encontró el post de Calama.');
  }
}
