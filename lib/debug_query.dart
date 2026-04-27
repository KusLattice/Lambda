import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final firestore = FirebaseFirestore.instance;
  
  print('--- BUSCANDO A JORGE ---');
  final userSnap = await firestore.collection('users')
      .where('email', isEqualTo: 'salgadoespina2@gmail.com')
      .get();
  
  if (userSnap.docs.isNotEmpty) {
    final doc = userSnap.docs.first;
    print('Jorge encontrado: ${doc.id}');
    print('Data: ${doc.data()}');
  } else {
    print('Jorge NO encontrado.');
  }
  
  print('\n--- BUSCANDO HOSPEDAJE EN CALAMA ---');
  final lodgingSnap = await firestore.collection('lodging_tracker').get();
  for (var doc in lodgingSnap.docs) {
    final data = doc.data();
    final text = '${data['title']} ${data['description']} ${data['locationName']}'.toLowerCase();
    if (text.contains('calama')) {
      print('Post encontrado: ${doc.id}');
      print('Data: $data');
    }
  }
}
