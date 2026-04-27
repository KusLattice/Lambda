import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:lambda_app/models/lodging_post_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/lodging_provider.dart';
import 'package:lambda_app/widgets/media_selector_field.dart';
import 'package:lambda_app/config/chile_regions.dart';

class CreateLodgingPostScreen extends ConsumerStatefulWidget {
  static const String routeName = '/create-lodging';
  final LodgingPost? initialPost;
  const CreateLodgingPostScreen({super.key, this.initialPost});

  @override
  ConsumerState<CreateLodgingPostScreen> createState() =>
      _CreateLodgingPostScreenState();
}

class _CreateLodgingPostScreenState
    extends ConsumerState<CreateLodgingPostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _coordsCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  List<File> _selectedImages = [];
  File? _selectedVideo;
  bool _isUploading = false;
  bool _isLocating = false;
  GeoPoint? _currentCoords;
  int _rating = 5;
  String? _selectedRegion;

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
      if (_currentCoords != null) {
        _coordsCtrl.text =
            '${_currentCoords!.latitude}, ${_currentCoords!.longitude}';
      }
      _priceCtrl.text = widget.initialPost!.pricePerNight?.toString() ?? '';
      _rating = widget.initialPost!.rating;
      _selectedRegion = widget.initialPost!.region;
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
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentCoords = GeoPoint(position.latitude, position.longitude);
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        _locationCtrl.text = '${place.street}, ${place.locality}';
        _coordsCtrl.text = '${position.latitude}, ${position.longitude}';
        final detectedRegion = matchChileRegion(place.administrativeArea);
        if (detectedRegion != null) {
          setState(() {
            _selectedRegion = detectedRegion;
          });
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _savePost() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedImages.isEmpty &&
        (widget.initialPost == null || widget.initialPost!.imageUrls.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sube al menos 1 foto.')));
      return;
    }

    setState(() => _isUploading = true);
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      setState(() => _isUploading = false);
      return;
    }

    try {
      double? price;
      if (_priceCtrl.text.trim().isNotEmpty) {
        price = double.tryParse(
          _priceCtrl.text.replaceAll(RegExp(r'[^0-9.]'), ''),
        );
      }

      final postData = LodgingPost(
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
        pricePerNight: price,
        rating: _rating,
        region: _selectedRegion,
      );

      if (widget.initialPost != null) {
        await ref
            .read(lodgingProvider.notifier)
            .updateLodgingPost(
              widget.initialPost!.id,
              {
                'title': postData.title,
                'description': postData.description,
                'locationName': postData.locationName,
                'coordinates': postData.coordinates,
                'pricePerNight': postData.pricePerNight,
                'rating': postData.rating,
                'region': postData.region,
              },
              imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
              videoFile: _selectedVideo,
              existingImageUrls: widget.initialPost!.imageUrls,
              existingVideoUrls: widget.initialPost!.videoUrls,
            );
      } else {
        await ref
            .read(lodgingProvider.notifier)
            .addLodgingPost(
              post: postData,
              imageFiles: _selectedImages,
              videoFile: _selectedVideo,
            );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Save error: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          icon: Icon(
            index < _rating ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 32,
          ),
          onPressed: () => setState(() => _rating = index + 1),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: Text(
          widget.initialPost != null
              ? 'Editar Hospedaje'
              : 'Registrar Hospedaje',
          style: const TextStyle(color: Colors.cyanAccent),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
      ),
      body: _isUploading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
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
                      accentColor: Colors.cyanAccent,
                      initialImageUrls: widget.initialPost?.imageUrls,
                      initialVideoUrl:
                          widget.initialPost?.videoUrls.isNotEmpty == true
                          ? widget.initialPost!.videoUrls.first
                          : null,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Nombre del Hotel/Lugar'),
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Dirección'),
                      onEditingComplete: _updateCoordsFromAddress,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _coordsCtrl,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            decoration: _inputDecoration('Coordenadas'),
                            onEditingComplete: _updateAddressFromCoords,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
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
                            'GPS',
                            style: TextStyle(color: Colors.black),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(
                        'Precio por noche (opcional)',
                      ).copyWith(prefixText: '\$ '),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: _inputDecoration('Reseña'),
                    ),
                    const SizedBox(height: 16),
                    _buildStarRating(),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRegion,
                      decoration: _inputDecoration('Región'),
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
                      onChanged: (val) => setState(() => _selectedRegion = val),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _savePost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.initialPost != null ? 'ACTUALIZAR' : 'GUARDAR',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.cyanAccent),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.cyanAccent),
      ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _coordsCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }
}
