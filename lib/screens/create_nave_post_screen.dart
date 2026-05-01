import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as native_geocoding;
import 'package:lambda_app/models/nave_post.dart';
import 'package:lambda_app/models/lat_lng.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/nave_provider.dart';
import 'package:lambda_app/services/geocoding_service.dart';
import 'package:lambda_app/config/app_config.dart';
import 'package:lambda_app/widgets/media_selector_field.dart';
import 'package:lambda_app/config/chile_regions.dart';

class CreateNavePostScreen extends ConsumerStatefulWidget {
  static const String routeName = '/create-nave-post';
  final String section;
  final NavePost? initialPost;
  const CreateNavePostScreen({
    super.key,
    required this.section,
    this.initialPost,
  });

  @override
  ConsumerState<CreateNavePostScreen> createState() =>
      _CreateNavePostScreenState();
}

class _CreateNavePostScreenState extends ConsumerState<CreateNavePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _addressController = TextEditingController();
  String? _selectedRegion;

  List<File> _selectedImages = [];
  File? _selectedVideo;
  bool _isLoading = false;

  void _onMediaChanged(List<File> images, File? video) {
    setState(() {
      _selectedImages = images;
      _selectedVideo = video;
    });
  }

  bool _isLocating = false;
  late final GeocodingService _geocoding = GeocodingService(
    apiKey: AppConfig.mapsApiKey,
  );

  @override
  void initState() {
    super.initState();
    if (widget.initialPost != null) {
      _titleController.text = widget.initialPost!.title;
      _contentController.text = widget.initialPost!.content;
      // Note: NavePost model might not have mediaType yet. Let's check.
      if (widget.initialPost!.location != null) {
        _latitudeController.text = widget.initialPost!.location!.latitude
            .toString();
        _longitudeController.text = widget.initialPost!.location!.longitude
            .toString();
      }
      if (widget.initialPost!.address != null) {
        _addressController.text = widget.initialPost!.address!;
      }
      _selectedRegion = widget.initialPost!.region;
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Servicios de ubicación deshabilitados.');
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permisos de ubicación denegados.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permisos permanentemente denegados.');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      _latitudeController.text = pos.latitude.toString();
      _longitudeController.text = pos.longitude.toString();

      final result = await _geocoding.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );
      if (result != null && result.formattedAddress != null) {
        _addressController.text = result.formattedAddress!;
      }

      // Obtener región nativa para normalizar
      List<native_geocoding.Placemark> placemarks = await native_geocoding
          .placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final region = matchChileRegion(placemarks.first.administrativeArea);
        if (region != null) {
          setState(() {
            _selectedRegion = region;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al ubicar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final postData = NavePost(
        id: widget.initialPost?.id ?? '',
        authorId: user.id,
        authorNickname: (user.apodo != null && user.apodo!.isNotEmpty)
            ? user.apodo!
            : user.nombre,
        authorFotoUrl: user.fotoUrl,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        section: widget.section,
        imageUrls: widget.initialPost?.imageUrls ?? [],
        videoUrls: widget.initialPost?.videoUrls ?? [],
        location:
            _latitudeController.text.isNotEmpty &&
                _longitudeController.text.isNotEmpty
            ? LatLng(
                double.parse(_latitudeController.text),
                double.parse(_longitudeController.text),
              )
            : null,
        address: _addressController.text.isNotEmpty
            ? _addressController.text
            : null,
        region: _selectedRegion,
        createdAt: widget.initialPost?.createdAt ?? DateTime.now(),
      );

      if (widget.initialPost != null) {
        await ref
            .read(naveProvider)
            .updatePost(
              postData.id,
              {
                'title': postData.title,
                'content': postData.content,
                'location': postData.location?.toJson(),
                'address': postData.address,
                'region': _selectedRegion,
              },
              imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
              videoFile: _selectedVideo,
              existingImageUrls: widget.initialPost!.imageUrls,
              existingVideoUrls: widget.initialPost!.videoUrls,
            );
      } else {
        await ref
            .read(naveProvider)
            .addPost(
              post: postData,
              imageFiles: _selectedImages,
              videoFile: _selectedVideo,
            );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.initialPost != null
                  ? 'Mensaje actualizado.'
                  : 'Mensaje enviado a La Nave.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.initialPost != null ? 'EDITAR POST' : 'NUEVO POST',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Título',
                        labelStyle: const TextStyle(color: Colors.greenAccent),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.greenAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),

                    // Selector de Región
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRegion,
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Región (Chile)'),
                      items: kRegionNames.map((r) {
                        return DropdownMenuItem(
                          value: r,
                          child: Text(r),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedRegion = val);
                      },
                    ),

                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _contentController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Contenido',
                        labelStyle: const TextStyle(color: Colors.greenAccent),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.greenAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Ubicación (Opcional)',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                      ),
                      icon: _isLocating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('¡Estoy aquí!'),
                      onPressed: _isLocating ? null : _getCurrentLocation,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latitudeController,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Latitud',
                              labelStyle: TextStyle(color: Colors.white38),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _longitudeController,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Longitud',
                              labelStyle: TextStyle(color: Colors.white38),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _addressController,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Dirección (Autocompletado)',
                        labelStyle: TextStyle(color: Colors.white38),
                      ),
                    ),
                    const SizedBox(height: 24),
                    MediaSelectorField(
                      onMediaChanged: _onMediaChanged,
                      accentColor: Colors.greenAccent,
                      initialImageUrls: widget.initialPost?.imageUrls,
                      initialVideoUrl:
                          widget.initialPost?.videoUrls.isNotEmpty == true
                          ? widget.initialPost!.videoUrls.first
                          : null,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _submit,
                      child: const Text('PUBLICAR EN EL FORO'),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.greenAccent),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: Colors.greenAccent.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.greenAccent),
      ),
    );
  }
}
