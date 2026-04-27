import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:lambda_app/models/food_post_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/food_provider.dart';
import 'package:lambda_app/config/chile_regions.dart';
import 'package:lambda_app/widgets/media_selector_field.dart';

class CreateFoodPostScreen extends ConsumerStatefulWidget {
  static const String routeName = '/create-food';
  final FoodPost? initialPost;
  const CreateFoodPostScreen({super.key, this.initialPost});

  @override
  ConsumerState<CreateFoodPostScreen> createState() =>
      _CreateFoodPostScreenState();
}

class _CreateFoodPostScreenState extends ConsumerState<CreateFoodPostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController(); // Dirección
  final _coordsCtrl = TextEditingController(); // Coordenadas

  List<File> _selectedImages = [];
  File? _selectedVideo;
  bool _isUploading = false;
  bool _isLocating = false;
  GeoPoint? _currentCoords;
  String? _selectedRegion;
  String? _selectedComuna;

  void _onMediaChanged(List<File> images, File? video) {
    setState(() {
      _selectedImages = images;
      _selectedVideo = video;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialPost != null) {
      _titleCtrl.text = widget.initialPost!.title;
      _descCtrl.text = widget.initialPost!.description;
      _locationCtrl.text = widget.initialPost!.locationName;
      _currentCoords = widget.initialPost!.coordinates;
      _selectedRegion = widget.initialPost!.region;
      _selectedComuna = widget.initialPost!.comuna;
      if (_currentCoords != null) {
        _coordsCtrl.text =
            '${_currentCoords!.latitude}, ${_currentCoords!.longitude}';
      }
    }
  }

  Future<void> _updateCoordsFromAddress() async {
    final address = _locationCtrl.text.trim();
    if (address.isEmpty) return;

    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        setState(() {
          _currentCoords = GeoPoint(loc.latitude, loc.longitude);
          _coordsCtrl.text = '${loc.latitude}, ${loc.longitude}';
        });
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
  }

  Future<void> _updateAddressFromCoords() async {
    final coordsText = _coordsCtrl.text.trim();
    if (coordsText.isEmpty) return;

    try {
      final parts = coordsText.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lon = double.tryParse(parts[1].trim());
        if (lat != null && lon != null) {
          _currentCoords = GeoPoint(lat, lon);
          List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            _locationCtrl.text = '${place.street}, ${place.locality}';
          }
        }
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    }
  }

  Future<void> _getLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception(
          'Los servicios de ubicación están deshabilitados. Encienda el GPS.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permisos de ubicación denegados.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Permisos de ubicación denegados permanentemente en ajustes.',
        );
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentCoords = GeoPoint(position.latitude, position.longitude);

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final address = '${place.street}, ${place.locality}';
          _locationCtrl.text = address;
          _coordsCtrl.text = '${position.latitude}, ${position.longitude}';
          
          final detectedRegion = matchChileRegion(place.administrativeArea);
          if (detectedRegion != null) {
            _selectedRegion = detectedRegion;
            _selectedComuna = null; // Resetear comuna al cambiar region automáticamente
          }
        } else {
          _locationCtrl.text = 'Sin dirección';
          _coordsCtrl.text = '${position.latitude}, ${position.longitude}';
        }
      } catch (e) {
        _locationCtrl.text = 'Error geocoding';
        _coordsCtrl.text = '${position.latitude}, ${position.longitude}';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _savePost() async {
    if (!_formKey.currentState!.validate()) return;

    // Al menos fotos o fotos previas
    if (_selectedImages.isEmpty &&
        (widget.initialPost?.imageUrls.isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, sube al menos 1 foto.')),
      );
      return;
    }

    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isUploading = true);

    try {
      final postData = FoodPost(
        id: widget.initialPost?.id ?? '',
        userId: user.id,
        authorName: (user.apodo != null && user.apodo!.isNotEmpty)
            ? user.apodo!
            : user.nombre,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        locationName: _locationCtrl.text.trim(),
        coordinates: _currentCoords,
        imageUrls: widget.initialPost?.imageUrls ?? [],
        videoUrls: widget.initialPost?.videoUrls ?? [],
        createdAt: widget.initialPost?.createdAt ?? DateTime.now(),
        rating: 5,
        region: _selectedRegion,
        comuna: _selectedComuna,
      );

      if (widget.initialPost != null) {
        await ref
            .read(foodProvider.notifier)
            .updateFoodPost(
              postData.id,
              {
                'title': postData.title,
                'description': postData.description,
                'locationName': postData.locationName,
                'coordinates': postData.coordinates,
                'region': postData.region,
                'comuna': postData.comuna,
              },
              imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
              videoFile: _selectedVideo,
              existingImageUrls: widget.initialPost!.imageUrls,
              existingVideoUrls: widget.initialPost!.videoUrls,
            );
      } else {
        await ref
            .read(foodProvider.notifier)
            .addFoodPost(
              post: postData,
              imageFiles: _selectedImages,
              videoFile: _selectedVideo,
            );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: Text(
          widget.initialPost != null ? 'Editar Picá' : 'Registrar Picá',
          style: const TextStyle(color: Colors.orangeAccent),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.orangeAccent),
      ),
      body: _isUploading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MediaSelectorField(
                      onMediaChanged: _onMediaChanged,
                      accentColor: Colors.orangeAccent,
                      initialImageUrls: widget.initialPost?.imageUrls,
                      initialVideoUrl:
                          widget.initialPost?.videoUrls.isNotEmpty == true
                          ? widget.initialPost!.videoUrls.first
                          : null,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '¿Qué comiste?',
                        labelStyle: TextStyle(color: Colors.orangeAccent),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.orangeAccent),
                        ),
                      ),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Ponele título a la weá'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        labelStyle: TextStyle(color: Colors.orangeAccent),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.orangeAccent),
                        ),
                      ),
                      onEditingComplete: _updateCoordsFromAddress,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _coordsCtrl,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Coordenadas',
                              labelStyle: TextStyle(color: Colors.orangeAccent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            ),
                            onEditingComplete: _updateAddressFromCoords,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 60,
                          child: ElevatedButton.icon(
                            onPressed: _isLocating ? null : _getLocation,
                            icon: _isLocating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Icon(
                                    Icons.my_location,
                                    color: Colors.black,
                                  ),
                            label: const Text(
                              '¡Estoy\nAquí!',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Reseña (opcional)',
                        labelStyle: TextStyle(color: Colors.orangeAccent),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.orangeAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRegion,
                      decoration: const InputDecoration(
                        labelText: 'Región',
                        labelStyle: TextStyle(color: Colors.orangeAccent),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.orangeAccent),
                        ),
                      ),
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Colors.white),
                      items: kRegionNames
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(
                                r,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() {
                        _selectedRegion = val;
                        _selectedComuna = null;
                      }),
                    ),
                    if (_selectedRegion != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedComuna,
                        decoration: const InputDecoration(
                          labelText: 'Comuna',
                          labelStyle: TextStyle(color: Colors.orangeAccent),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.orangeAccent),
                          ),
                        ),
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white),
                        items: (kChileRegions[_selectedRegion] ?? [])
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedComuna = val),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _savePost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.initialPost != null
                            ? 'ACTUALIZAR PICÁ'
                            : 'GUARDAR PICÁ',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _coordsCtrl.dispose();
    super.dispose();
  }
}
