import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Reproductor de video integrado basado en video_player + chewie.
///
/// Robusto ante navegación rápida: usa controladores nullable y guard
/// [_disposed] para evitar LateInitializationError y setState en widgets
/// desmont ados durante la inicialización asíncrona.
class IntegratedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;
  final bool looping;
  final double aspectRatio;
  final bool isAsset; // false significa archivo de sistema local (File)

  const IntegratedVideoPlayer({
    super.key,
    required this.videoUrl,
    this.autoPlay = false,
    this.looping = false,
    this.aspectRatio = 16 / 9,
    this.isAsset =
        true, // Por defecto asumimos que es una URL o Asset controlado
  });

  @override
  State<IntegratedVideoPlayer> createState() => _IntegratedVideoPlayerState();
}

class _IntegratedVideoPlayerState extends State<IntegratedVideoPlayer> {
  // Nullable para poder hacer guard en dispose() y evitar LateInitializationError
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  bool _isInitializing = true;
  bool _hasError = false;
  String? _errorMessage;

  /// Guard para evitar setState después de dispose cuando la inicialización
  /// es asíncrona y el usuario navega atrás antes de que termine.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    if (widget.videoUrl.isEmpty) {
      if (!_disposed && mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'URL de video vacía.';
          _isInitializing = false;
        });
      }
      return;
    }

    try {
      final controller = widget.isAsset
          ? VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
          : VideoPlayerController.file(File(widget.videoUrl));

      // Asignar antes de await para que dispose() lo encuentre si es cancelado
      _videoController = controller;

      await controller.initialize();

      // Si fue disposed mientras esperábamos, limpiar y salir
      if (_disposed) {
        controller.dispose();
        return;
      }

      final chewieController = ChewieController(
        videoPlayerController: controller,
        aspectRatio: controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : widget.aspectRatio,
        autoPlay: widget.autoPlay,
        looping: widget.looping,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        // Colores acorde al tema Lambda
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.greenAccent,
          handleColor: Colors.greenAccent,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.white24,
        ),
        placeholder: const _VideoLoadingPlaceholder(),
        errorBuilder: (context, errorMessage) =>
            _VideoErrorWidget(message: errorMessage),
      );
      _chewieController = chewieController;

      if (!_disposed && mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      debugPrint('[IntegratedVideoPlayer] Error al inicializar: $e');
      if (!_disposed && mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Dispose en orden: chewie primero, luego el controller base
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _VideoErrorWidget(message: _errorMessage);
    }

    if (_isInitializing || _chewieController == null) {
      return const _VideoLoadingPlaceholder();
    }

    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Chewie(controller: _chewieController!),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets de apoyo — privados al archivo
// ---------------------------------------------------------------------------

class _VideoLoadingPlaceholder extends StatelessWidget {
  const _VideoLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.greenAccent,
                strokeWidth: 2,
              ),
              SizedBox(height: 10),
              Text(
                'Cargando video...',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoErrorWidget extends StatelessWidget {
  final String? message;
  const _VideoErrorWidget({this.message});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.video_camera_back_outlined,
              color: Colors.white24,
              size: 40,
            ),
            const SizedBox(height: 8),
            const Text(
              'No se pudo reproducir el video',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
