import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

class OtaUpdateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> checkForUpdates(BuildContext context) async {
    try {
      // 1. Obtener versión actual de la app
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;
      final int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 2. Obtener versión más reciente desde Firestore
      debugPrint('OTA: Verificando Firestore metadata/app_info...');
      final docSnapshot = await _firestore
          .collection('metadata')
          .doc('app_info')
          .get();

      if (!docSnapshot.exists) {
        debugPrint(
          'OTA ERROR: El documento metadata/app_info no existe en Firestore.',
        );
        return;
      }

      final data = docSnapshot.data()!;
      final String latestVersion = data['latest_version'] ?? '1.0.0';
      final String displayVersion = data['display_version'] ?? latestVersion;
      final int latestBuildNumber = data['latest_build_number'] ?? 0;
      final String downloadUrl = data['apk_download_url'] ?? '';

      debugPrint('OTA: Actual (v$currentVersion, build $currentBuildNumber)');
      debugPrint('OTA: Remota (v$latestVersion, build $latestBuildNumber, display $displayVersion)');
      debugPrint('OTA: URL: $downloadUrl');

      // 3. Comparar
      bool hasUpdate = false;
      if (latestBuildNumber > currentBuildNumber) {
        hasUpdate = true;
      } else if (latestBuildNumber == currentBuildNumber &&
          _compareVersions(latestVersion, currentVersion) > 0) {
        hasUpdate = true;
      }

      debugPrint('OTA: ¿Tiene actualización?: $hasUpdate');

      if (hasUpdate && downloadUrl.isNotEmpty && context.mounted) {
        debugPrint('OTA: Mostrando diálogo de actualización.');
        _showUpdateDialog(
          context: context,
          latestVersion: displayVersion,
          updateNotes:
              data['update_notes'] ?? 'Nueva actualización disponible.',
          downloadUrl: downloadUrl,
          isMandatory: data['is_mandatory'] ?? false,
        );
      }
    } catch (e) {
      debugPrint('Error en verificacion OTA: $e');
    }
  }

  int _compareVersions(String v1, String v2) {
    List<int> vals1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> vals2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      int val1 = vals1.length > i ? vals1[i] : 0;
      int val2 = vals2.length > i ? vals2[i] : 0;
      if (val1 > val2) return 1;
      if (val1 < val2) return -1;
    }
    return 0;
  }

  void _showUpdateDialog({
    required BuildContext context,
    required String latestVersion,
    required String updateNotes,
    required String downloadUrl,
    required bool isMandatory,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (BuildContext context) {
        return _UpdateDialog(
          latestVersion: latestVersion,
          updateNotes: updateNotes,
          downloadUrl: downloadUrl,
          isMandatory: isMandatory,
        );
      },
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String latestVersion;
  final String updateNotes;
  final String downloadUrl;
  final bool isMandatory;

  const _UpdateDialog({
    required this.latestVersion,
    required this.updateNotes,
    required this.downloadUrl,
    required this.isMandatory,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0;
  String _statusMessage = '';

  Future<void> _downloadAndInstall() async {
    // Pedir permisos de almacenamiento en Android antiguos.
    if (Platform.isAndroid) {
      if (await Permission.requestInstallPackages.request().isDenied) {
        setState(() {
          _statusMessage = 'Se necesita permiso para instalar.';
        });
        return;
      }
    }

    setState(() {
      _isDownloading = true;
      _statusMessage = 'Descargando actualización...';
    });

    try {
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final String savePath = '${tempDir.path}/lambda_app_update.apk';

      await dio.download(
        widget.downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      setState(() {
        _statusMessage = 'Iniciando instalación...';
      });

      final result = await OpenFilex.open(savePath);

      if (result.type != ResultType.done) {
        setState(() {
          _statusMessage = 'Error al abrir el APK: ${result.message}';
          _isDownloading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Error en la descarga: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !widget.isMandatory && !_isDownloading,
      child: AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: Colors.greenAccent),
            const SizedBox(width: 10),
            Text(
              'Versión ${widget.latestVersion} Disponible',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.updateNotes,
              style: const TextStyle(color: Colors.white70),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[800],
                color: Colors.greenAccent,
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}% - $_statusMessage',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ] else if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          if (!widget.isMandatory && !_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Más tarde',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          if (!_isDownloading)
            ElevatedButton(
              onPressed: _downloadAndInstall,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Actualizar Ahora'),
            ),
        ],
      ),
    );
  }
}
