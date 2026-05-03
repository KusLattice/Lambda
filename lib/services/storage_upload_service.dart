import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageUploadService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Sube imágenes a [basePath] y retorna sus URLs.
  static Future<List<String>> uploadImages(
    List<File> files,
    String basePath,
  ) async {
    final urls = <String>[];
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < files.length; i++) {
      final ref = _storage.ref().child('$basePath/${ts}_img_$i.jpg');
      await ref.putFile(files[i]);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  /// Sube un video y retorna su URL.
  static Future<String?> uploadVideo(File file, String basePath) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref().child('$basePath/${ts}_vid.mp4');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  /// Sube una foto de perfil a un path fijo para sobreescribir.
  static Future<String> uploadProfilePhoto(File file, String userId) async {
    final ref = _storage.ref().child('users/$userId/profile.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  /// Borra una lista de URLs de Storage. Silencia errores (404, permisos).
  static Future<void> deleteUrls(List<String> urls) async {
    for (final url in urls) {
      if (url.isEmpty) continue;
      try {
        await _storage.refFromURL(url).delete();
      } catch (e) {
        // Silenciamos errores (ej: el archivo ya no existe)
        print('Error deleting $url: $e');
      }
    }
  }
}
