import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:lambda_app/models/fiber_cut_report.dart';

class FiberCutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Stream de reportes activos (no resueltos) ordenados por fecha descendente.
  Stream<List<FiberCutReport>> getActiveReports() {
    return _firestore
        .collection('fiber_cut_reports')
        .where('isResolved', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) => FiberCutReport.fromMap(doc.data(), doc.id))
              .toList();
        });
  }

  /// Crea un nuevo reporte con soporte multimedia múltiple.
  Future<void> createReport({
    required String reporterId,
    required String reporterNickname,
    String? reporterFotoUrl,
    required double latitude,
    required double longitude,
    String? address,
    List<File> imageFiles = const [],
    File? videoFile,
    String? description,
    String? region,
    String? comuna,
  }) async {
    final List<String> imageUrls = [];
    final List<String> videoUrls = [];

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Subir imágenes
    for (int i = 0; i < imageFiles.length; i++) {
      final ref = _storage.ref().child('fiber_cuts/$timestamp/img_$i.jpg');
      await ref.putFile(imageFiles[i]);
      imageUrls.add(await ref.getDownloadURL());
    }

    // Subir video (máx 1)
    if (videoFile != null) {
      final ref = _storage.ref().child('fiber_cuts/$timestamp/video.mp4');
      await ref.putFile(videoFile);
      videoUrls.add(await ref.getDownloadURL());
    }

    final report = {
      'reporterId': reporterId,
      'reporterNickname': reporterNickname,
      'reporterFotoUrl': reporterFotoUrl,
      'location': {'latitude': latitude, 'longitude': longitude},
      'address': address,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'photoUrl': imageUrls.isNotEmpty
          ? imageUrls.first
          : null, // Retrocompatibilidad
      'createdAt': FieldValue.serverTimestamp(),
      'isResolved': false,
      'description': description,
      'region': region,
      'comuna': comuna,
    };

    await _firestore.collection('fiber_cut_reports').add(report);
  }

  /// Marca un reporte como resuelto.
  Future<void> resolveReport(String reportId) async {
    await _firestore.collection('fiber_cut_reports').doc(reportId).update({
      'isResolved': true,
    });
  }

  /// Actualiza un reporte existente
  Future<void> updateReport(String reportId, Map<String, dynamic> data) async {
    await _firestore.collection('fiber_cut_reports').doc(reportId).update(data);
  }

  /// Elimina un reporte permanentemente
  Future<void> deleteReport(String reportId) async {
    await _firestore.collection('fiber_cut_reports').doc(reportId).delete();
  }
}
