import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:lambda_app/models/secret_hack_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/hack_provider.dart';
import 'package:lambda_app/widgets/media_selector_field.dart';

class CreateHackScreen extends ConsumerStatefulWidget {
  static const String routeName = '/create-hack';
  final SecretHack? initialHack;
  const CreateHackScreen({super.key, this.initialHack});

  @override
  ConsumerState<CreateHackScreen> createState() => _CreateHackScreenState();
}

class _CreateHackScreenState extends ConsumerState<CreateHackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _locationCtrl = TextEditingController();

  final _titleFocus = FocusNode();
  final _locationFocus = FocusNode();

  bool _isSaving = false;
  String _selectedCategory = 'Datitos';
  bool _isGettingLocation = false;

  List<File> _selectedImages = [];
  File? _selectedVideo;

  void _onMediaChanged(List<File> images, File? video) {
    setState(() {
      _selectedImages = images;
      _selectedVideo = video;
    });
  }

  final List<String> _categories = ['Preguntas', 'Datitos', 'Claves'];

  @override
  void initState() {
    super.initState();
    if (widget.initialHack != null) {
      _titleController.text = widget.initialHack!.title;
      _contentController.text = widget.initialHack!.info;
      if (widget.initialHack!.location != null) {
        _locationCtrl.text = widget.initialHack!.location!;
      }
      _selectedCategory = widget.initialHack!.category;
    }
    _titleFocus.addListener(_onTitleFocusChanged);
    _locationFocus.addListener(_onLocationFocusChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _locationCtrl.dispose();
    _titleFocus.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  void _onTitleFocusChanged() async {
    if (!_titleFocus.hasFocus &&
        (_selectedCategory == 'Claves' || _selectedCategory == 'Datitos') &&
        _titleController.text.isNotEmpty &&
        _locationCtrl.text.isEmpty) {
      try {
        List<Location> locations = await locationFromAddress(
          _titleController.text,
        );
        if (locations.isNotEmpty && mounted) {
          setState(() {
            _locationCtrl.text =
                '${locations.first.latitude}, ${locations.first.longitude}';
          });
        }
      } catch (e) {
        debugPrint('Geocoding error: $e');
      }
    }
  }

  void _onLocationFocusChanged() async {
    if (!_locationFocus.hasFocus &&
        (_selectedCategory == 'Claves' || _selectedCategory == 'Datitos') &&
        _locationCtrl.text.isNotEmpty &&
        _titleController.text.isEmpty) {
      try {
        final parts = _locationCtrl.text.split(',');
        if (parts.length == 2) {
          double lat = double.parse(parts[0].trim());
          double lng = double.parse(parts[1].trim());
          List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isNotEmpty && mounted) {
            final p = placemarks.first;
            String address = '${p.street ?? ''}, ${p.locality ?? ''}'.trim();
            if (address.startsWith(',')) address = address.substring(1).trim();
            if (address.endsWith(',')) {
              address = address.substring(0, address.length - 1).trim();
            }
            setState(() {
              _titleController.text = address;
            });
          }
        }
      } catch (e) {
        debugPrint('Reverse geocoding error: $e');
      }
    }
  }

  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Los servicios de ubicación están desactivados.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permisos de ubicación denegados.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permisos denegados permanentemente.');
      }

      Position position = await Geolocator.getCurrentPosition();

      setState(() {
        _locationCtrl.text = '${position.latitude}, ${position.longitude}';
      });

      if (_titleController.text.isEmpty) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
          if (placemarks.isNotEmpty && mounted) {
            final p = placemarks.first;
            String address = '${p.street ?? ''}, ${p.locality ?? ''}'.trim();
            if (address.startsWith(',')) address = address.substring(1).trim();
            if (address.endsWith(',')) {
              address = address.substring(0, address.length - 1).trim();
            }
            setState(() {
              _titleController.text = address;
            });
          }
        } catch (e) {
          debugPrint('Reverse geocoding from getting location error: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _saveHack() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      setState(() => _isSaving = false);
      return;
    }

    final hack = SecretHack(
      id: widget.initialHack?.id ?? '',
      userId: user.id,
      authorName: (user.apodo != null && user.apodo!.isNotEmpty)
          ? user.apodo!
          : user.nombre,
      title: _titleController.text.trim(),
      info: _contentController.text.trim(),
      category: _selectedCategory,
      location:
          (_selectedCategory == 'Claves' || _selectedCategory == 'Datitos') &&
              _locationCtrl.text.trim().isNotEmpty
          ? _locationCtrl.text.trim()
          : null,
      createdAt: widget.initialHack?.createdAt ?? DateTime.now(),
    );

    try {
      if (widget.initialHack != null) {
        await ref
            .read(hacksProvider.notifier)
            .updateHack(
              hack.id,
              {
                'title': hack.title,
                'info': hack.info,
                'category': hack.category,
                'location': hack.location,
              },
              imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
              videoFile: _selectedVideo,
              existingImageUrls: widget.initialHack!.imageUrls,
              existingVideoUrls: widget.initialHack!.videoUrls,
            );
      } else {
        await ref
            .read(hacksProvider.notifier)
            .addHack(
              hack: hack,
              imageFiles: _selectedImages,
              videoFile: _selectedVideo,
            );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anotado en La Libretita secreta.'),
            backgroundColor: Colors.greenAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.initialHack != null
              ? 'EDITAR DATO SECRETO'
              : 'ANOTAR EN LA LIBRETITA',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.greenAccent),
      ),
      body: _isSaving
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
                    const Icon(
                      Icons.menu_book,
                      size: 60,
                      color: Colors.greenAccent,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Añade un nuevo apunte a La Libretita',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    MediaSelectorField(
                      onMediaChanged: _onMediaChanged,
                      accentColor: Colors.greenAccent,
                      initialImageUrls: widget.initialHack?.imageUrls,
                      initialVideoUrl:
                          widget.initialHack?.videoUrls.isNotEmpty == true
                          ? widget.initialHack!.videoUrls.first
                          : null,
                    ),
                    const SizedBox(height: 32),

                    // Category Selector
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.greenAccent),
                      decoration: InputDecoration(
                        labelText: 'Categoría',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.grey[900],
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.greenAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                      items: _categories.map((String cat) {
                        return DropdownMenuItem<String>(
                          value: cat,
                          child: Text(cat),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedCategory = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _titleController,
                      focusNode: _titleFocus,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText:
                            (_selectedCategory == 'Claves' ||
                                _selectedCategory == 'Datitos')
                            ? 'Dirección / Ubicación'
                            : 'Título corto',
                        labelStyle: const TextStyle(color: Colors.greenAccent),
                        filled: true,
                        fillColor: Colors.grey[900],
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

                    TextFormField(
                      controller: _contentController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: 'Información / Detalle',
                        labelStyle: const TextStyle(color: Colors.greenAccent),
                        filled: true,
                        fillColor: Colors.grey[900],
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

                    if (_selectedCategory == 'Claves' ||
                        _selectedCategory == 'Datitos') ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _locationCtrl,
                              focusNode: _locationFocus,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Coordenadas GPS (Opcional)',
                                labelStyle: const TextStyle(
                                  color: Colors.greenAccent,
                                ),
                                filled: true,
                                fillColor: Colors.grey[900],
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.greenAccent.withValues(alpha: 0.5),
                                  ),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isGettingLocation ? null : _getLocation,
                            icon: _isGettingLocation
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
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
                              '¡Estoy aquí!',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _saveHack,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'GUARDAR EN LA LIBRETITA',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
