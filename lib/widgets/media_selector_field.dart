import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lambda_app/widgets/video_player_widget.dart';

class MediaSelectorField extends StatefulWidget {
  final List<File> initialImages;
  final File? initialVideo;
  final List<String>? initialImageUrls;
  final String? initialVideoUrl;
  final Function(List<File> images, File? video) onMediaChanged;
  final Color accentColor;

  const MediaSelectorField({
    super.key,
    this.initialImages = const [],
    this.initialVideo,
    this.initialImageUrls,
    this.initialVideoUrl,
    required this.onMediaChanged,
    this.accentColor = Colors.greenAccent,
  });

  @override
  State<MediaSelectorField> createState() => _MediaSelectorFieldState();
}

class _MediaSelectorFieldState extends State<MediaSelectorField> {
  late List<File> _images;
  File? _video;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _images = List.from(widget.initialImages);
    _video = widget.initialVideo;
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 70);
    if (picked.isNotEmpty) {
      setState(() {
        _images.addAll(picked.map((x) => File(x.path)));
        if (_images.length > 3) {
          _images = _images.sublist(0, 3);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Límite de 3 imágenes alcanzado.')),
          );
        }
      });
      widget.onMediaChanged(_images, _video);
    }
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 10),
    );
    if (picked != null) {
      setState(() {
        _video = File(picked.path);
      });
      widget.onMediaChanged(_images, _video);
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
    widget.onMediaChanged(_images, _video);
  }

  void _removeVideo() {
    setState(() {
      _video = null;
    });
    widget.onMediaChanged(_images, _video);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MULTIMEDIA (MÁX 3 FOTOS + 1 VIDEO)',
          style: TextStyle(
            color: Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Imágenes Remotas (Existentes)
            if (widget.initialImageUrls != null)
              ...widget.initialImageUrls!.asMap().entries.map((entry) {
                final url = entry.value;
                // Si la imagen fue "reemplazada" localmente (en una lógica más compleja), pero aquí
                // para simplificar, si hay archivos nuevos, ocultamos los remotos o los mezclamos.
                // Decisión: Mezclarlos hasta el tope de 3.
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey[900],
                          child: const Icon(Icons.error, color: Colors.white24),
                        ),
                      ),
                    ),
                    // Nota: Para borrar fotos remotas en edición necesitaríamos un callback específico 'onRemoveRemoteImage'.
                    // Por ahora, para mantener simpleza técnica pedida, nos enfocamos en nuevas subidas.
                  ],
                );
              }),
            // Imágenes seleccionadas locales
            ..._images.asMap().entries.map((entry) {
              final idx = entry.key;
              final file = entry.value;
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      file,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImage(idx),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              );
            }),
            // Botón Agregar Foto (considerando remotas + locales)
            if ((_images.length + (widget.initialImageUrls?.length ?? 0)) < 3)
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.accentColor.withOpacity(0.3),
                    ),
                  ),
                  child: Icon(Icons.add_a_photo, color: widget.accentColor),
                ),
              ),
            // Botón Agregar Video
            if (_video == null && widget.initialVideoUrl == null)
              GestureDetector(
                onTap: _pickVideo,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.accentColor.withOpacity(0.3),
                    ),
                  ),
                  child: Icon(Icons.video_call, color: widget.accentColor),
                ),
              ),
          ],
        ),
        if (_video != null || widget.initialVideoUrl != null) ...[
          const SizedBox(height: 16),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: IntegratedVideoPlayer(
                  key: Key(_video?.path ?? widget.initialVideoUrl!),
                  videoUrl: _video?.path ?? widget.initialVideoUrl!,
                  isAsset: false,
                ),
              ),
              if (_video != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: _removeVideo,
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black54,
                      child: Icon(
                        Icons.delete,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8.0, left: 4),
            child: Text(
              'Video limitado a 10 segundos.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}
