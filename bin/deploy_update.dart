import 'dart:io';
import 'dart:convert';

/// Script de Despliegue Pro Senior para Lambda App.
/// Automatiza la subida del APK a Firebase Storage y la actualización de Firestore.
void main(List<String> args) async {
  print('🚀 Iniciando Despliegue Lambda OTA...');

  // 1. Validar pubspec.yaml
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('❌ ERROR: No se encuentra pubspec.yaml en el directorio actual.');
    exit(1);
  }

  final lines = await pubspecFile.readAsLines();
  String? version;
  int? buildNumber;

  for (var line in lines) {
    if (line.startsWith('version:')) {
      final parts = line.split(':')[1].trim().split('+');
      version = parts[0];
      buildNumber = int.tryParse(parts[1]);
      break;
    }
  }

  if (version == null || buildNumber == null) {
    print('❌ ERROR: No se pudo extraer la versión/build de pubspec.yaml.');
    exit(1);
  }

  print('📦 Detectada Versión: $version (Build $buildNumber)');

  // 2. Localizar APK
  final apkFile = File('build/app/outputs/flutter-apk/app-release.apk');
  // También revisamos la raíz si Seba lo movió ahí
  final altApkFile = File('lambda_v0.2_beta.apk'); 

  File targetApk = apkFile;
  if (!apkFile.existsSync()) {
    if (altApkFile.existsSync()) {
      targetApk = altApkFile;
    } else {
      print('⚠️ ADVERTENCIA: No se encontró build/app/outputs/flutter-apk/app-release.apk');
      print('Intentando buscar cualquier APK generado recientemente...');
      // Búsqueda simple
      final dir = Directory('.');
      final files = dir.listSync();
      final apks = files.where((f) => f.path.endsWith('.apk')).toList();
      if (apks.isEmpty) {
        print('❌ ERROR: No se encontró ningún APK para subir.');
        print('Corre "flutter build apk --release" primero.');
        exit(1);
      }
      targetApk = File(apks.first.path);
    }
  }

  print('📍 Usando APK: ${targetApk.path}');

  // 3. Subir a Firebase Storage
  // Usamos el nombre del archivo en el bucket: lambda_app_latest.apk
  final storagePath = 'gs://lambda-c242a.appspot.com/updates/lambda_app_v$version.apk';
  print('☁️ Subiendo a Firebase Storage...');
  
  final uploadResult = await Process.run('firebase', [
    'storage:upload',
    targetApk.path,
    storagePath,
  ], runInShell: true);

  if (uploadResult.exitCode != 0) {
    print('❌ ERROR al subir a Storage: ${uploadResult.stderr}');
    exit(1);
  }
  print('✅ APK subida exitosamente.');

  // 4. Obtener URL de descarga (simplificado para Seba)
  // La URL de Firebase Storage tiene un patrón. Para que sea pública,
  // Seba debe tener las reglas de storage configuradas para lectura pública en /updates/.
  // O usar la URL con token. Como no podemos obtener el token fácilmente por CLI puro sin jq,
  // generamos el enlace directo que suele funcionar si las reglas son públicas.
  final downloadUrl = 'https://firebasestorage.googleapis.com/v0/b/lambda-c242a.appspot.com/o/updates%2Flambda_app_v$version.apk?alt=media';

  // 5. Actualizar Firestore
  print('🔥 Actualizando metadatos en Firestore...');
  
  final updateNotes = args.isNotEmpty ? args.join(' ') : 'Mejoras de estabilidad y mística técnica.';
  
  final Map<String, dynamic> appInfo = {
    'latest_version': version,
    'latest_build_number': buildNumber,
    'apk_download_url': downloadUrl,
    'update_notes': updateNotes,
    'is_mandatory': false,
    'updated_at': DateTime.now().toIso8601String(),
  };

  // Escribimos un temporal para que el CLI lo suba
  final tempJson = File('temp_app_info.json');
  await tempJson.writeAsString(jsonEncode(appInfo));

  final firestoreResult = await Process.run('firebase', [
    'firestore:documents:set',
    'metadata/app_info',
    'temp_app_info.json',
  ], runInShell: true);

  await tempJson.delete();

  if (firestoreResult.exitCode != 0) {
    print('❌ ERROR al actualizar Firestore: ${firestoreResult.stderr}');
    exit(1);
  }

  print('\n🎯 DESPLIEGUE COMPLETADO CON ÉXITO.');
  print('Versión $version (Build $buildNumber) ya está disponible para el equipo.');
}
