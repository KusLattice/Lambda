import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class LambdaImagePicker {
  static const Color backgroundColor = Color(0xFF121212);
  static const Color accentColor = Colors.greenAccent;

  static Future<List<XFile>> pickImages(BuildContext context, {
    String? title,
  }) async {
    final ImagePicker picker = ImagePicker();
    
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildSourcePicker(context, isVideo: false, customTitle: title),
    );

    if (source == null) return [];

    if (source == ImageSource.camera) {
      final file = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      return file != null ? [file] : [];
    } else {
      return await picker.pickMultiImage(imageQuality: 70);
    }
  }

  static Future<XFile?> pickSingleImage(BuildContext context, {
    String? title,
  }) async {
    final ImagePicker picker = ImagePicker();
    
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildSourcePicker(context, isVideo: false, customTitle: title),
    );

    if (source == null) return null;

    return await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
  }

  static Future<XFile?> pickVideo(BuildContext context, {
    String? title,
  }) async {
    final ImagePicker picker = ImagePicker();
    
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildSourcePicker(context, isVideo: true, customTitle: title),
    );

    if (source == null) return null;

    return await picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
    );
  }

  static Widget _buildSourcePicker(BuildContext context, {required bool isVideo, String? customTitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            customTitle ?? (isVideo ? 'SUBIR VIDEO' : 'SUBIR IMAGEN'),
            style: const TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSourceOption(
                context,
                icon: isVideo ? Icons.videocam_rounded : Icons.camera_alt_rounded,
                label: 'CÁMARA',
                source: ImageSource.camera,
              ),
              _buildSourceOption(
                context,
                icon: isVideo ? Icons.video_library_rounded : Icons.photo_library_rounded,
                label: 'GALERÍA',
                source: ImageSource.gallery,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  static Widget _buildSourceOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
