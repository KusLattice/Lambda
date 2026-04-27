import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lambda_app/widgets/video_player_widget.dart';

/// Sección de video reutilizable para pantallas de creación y visualización.
///
/// En **modo visualización** (`videoUrls` no vacío, sin [onVideosChanged]):
/// muestra la lista de reproductores para las URLs provistas.
///
/// En **modo edición** (`onVideosChanged` no null):
/// muestra el botón de agregar video y gestiona el estado interno de la lista.
///
/// Este widget centraliza toda la lógica de subida a Firebase Storage,
/// evitando duplicarla en cada sección (Hospedaje, Picás, Mercado, Chat…).
class VideoSection extends StatefulWidget {
  /// URLs de videos ya guardados (modo display o edición con contenido previo).
  final List<String> videoUrls;

  /// Callback llamado cuando la lista de URLs cambia (modo edición).
  /// Si es null, el widget es solo de visualización.
  final void Function(List<String> urls)? onVideosChanged;

  /// Ruta de Firebase Storage donde subir los videos (ej: 'food_videos').
  final String storagePath;

  /// Color de acento para el botón y el player (default: greenAccent).
  final Color accentColor;

  /// Límite de videos permitidos. Default: 1.
  final int maxVideos;

  const VideoSection({
    super.key,
    required this.videoUrls,
    this.onVideosChanged,
    this.storagePath = 'videos',
    this.accentColor = Colors.greenAccent,
    this.maxVideos = 1,
  });

  @override
  State<VideoSection> createState() => _VideoSectionState();
}

class _VideoSectionState extends State<VideoSection> {
  late List<String> _urls;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _urls = List.from(widget.videoUrls);
  }

  @override
  void didUpdateWidget(VideoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrls != widget.videoUrls) {
      _urls = List.from(widget.videoUrls);
    }
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _isUploading = true);
    try {
      final file = File(picked.path);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      final ref = FirebaseStorage.instance
          .ref()
          .child(widget.storagePath)
          .child(fileName);

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      if (!mounted) return;
      setState(() {
        _urls.add(url);
        _isUploading = false;
      });
      widget.onVideosChanged?.call(_urls);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al subir video: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _removeUrl(int index) {
    setState(() => _urls.removeAt(index));
    widget.onVideosChanged?.call(_urls);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.onVideosChanged != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reproductores para cada URL
        for (int i = 0; i < _urls.length; i++) ...[
          Stack(
            children: [
              IntegratedVideoPlayer(
                key: Key('vidplayer_${_urls[i]}'),
                videoUrl: _urls[i],
                isAsset: _urls[i].startsWith('http'),
              ),
              // Botón de quitar solo en modo edición
              if (isEditing)
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => _removeUrl(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // Botón de agregar (solo modo edición si no superamos el límite)
        if (isEditing && _urls.length < widget.maxVideos)
          _isUploading
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.accentColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Subiendo video...',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: widget.accentColor.withOpacity(0.5),
                    ),
                    foregroundColor: widget.accentColor,
                  ),
                  icon: const Icon(Icons.video_call_outlined),
                  label: const Text('Adjuntar video'),
                  onPressed: _pickAndUpload,
                ),
      ],
    );
  }
}
