import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/market_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/market_provider.dart';
import 'package:lambda_app/widgets/media_selector_field.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as native_geocoding;
import 'package:lambda_app/services/geocoding_service.dart';
import 'package:lambda_app/config/app_config.dart';
import 'package:lambda_app/config/chile_regions.dart';

class CreateMarketItemScreen extends ConsumerStatefulWidget {
  static const String routeName = '/create-market-item';
  final MarketItem? initialItem;
  const CreateMarketItemScreen({super.key, this.initialItem});

  @override
  ConsumerState<CreateMarketItemScreen> createState() =>
      _CreateMarketItemScreenState();
}

class _CreateMarketItemScreenState
    extends ConsumerState<CreateMarketItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  MarketCategory _selectedCategory = MarketCategory.Herramientas;
  String? _selectedRegion;
  bool _isLocating = false;

  final _geocoding = GeocodingService(apiKey: AppConfig.mapsApiKey);

  List<File> _selectedImages = [];
  File? _selectedVideo;
  bool _isLoading = false;

  void _onMediaChanged(List<File> images, File? video) {
    setState(() {
      _selectedImages = images;
      _selectedVideo = video;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialItem != null) {
      _titleController.text = widget.initialItem!.title;
      _descriptionController.text = widget.initialItem!.description;
      _priceController.text = widget.initialItem!.price?.toString() ?? '';
      _selectedCategory = widget.initialItem!.category;
      _selectedRegion = widget.initialItem!.region;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS Desactivado');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permisos denegados');
        }
      }

      final pos = await Geolocator.getCurrentPosition();
      List<native_geocoding.Placemark> placemarks = await native_geocoding
          .placemarkFromCoordinates(pos.latitude, pos.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final normalizedReg = matchChileRegion(place.administrativeArea);
        if (normalizedReg != null) {
          setState(() {
            _selectedRegion = normalizedReg;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedImages.isEmpty &&
        (widget.initialItem == null || widget.initialItem!.imageUrls.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sube al menos 1 imagen del producto.')),
      );
      return;
    }

    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final double? price = _priceController.text.isNotEmpty
          ? double.tryParse(_priceController.text)
          : null;

      final itemData = MarketItem(
        id: widget.initialItem?.id ?? '',
        sellerId: user.id,
        sellerName: (user.apodo != null && user.apodo!.isNotEmpty)
            ? user.apodo!
            : user.nombre,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: price,
        category: _selectedCategory,
        imageUrls: widget.initialItem?.imageUrls ?? [],
        videoUrls: widget.initialItem?.videoUrls ?? [],
        createdAt: widget.initialItem?.createdAt ?? DateTime.now(),
        region: _selectedRegion,
      );

      if (widget.initialItem != null) {
        await ref
            .read(marketNotifierProvider.notifier)
            .updateMarketItem(
              widget.initialItem!.id,
              {
                'title': itemData.title,
                'description': itemData.description,
                'price': itemData.price,
                'category': itemData.category.name,
                'region': _selectedRegion,
              },
              imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
              videoFile: _selectedVideo,
              existingImageUrls: widget.initialItem!.imageUrls,
              existingVideoUrls: widget.initialItem!.videoUrls,
            );
      } else {
        await ref
            .read(marketNotifierProvider.notifier)
            .addMarketItem(
              item: itemData,
              imageFiles: _selectedImages,
              videoFile: _selectedVideo,
            );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Publicación guardada exitosamente.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.initialItem != null
              ? 'EDITAR PUBLICACIÓN'
              : 'NUEVA PUBLICACIÓN',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        backgroundColor: Colors.grey[900],
        iconTheme: const IconThemeData(color: Colors.orangeAccent),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MediaSelectorField(
                      onMediaChanged: _onMediaChanged,
                      accentColor: Colors.orangeAccent,
                      initialImageUrls: widget.initialItem?.imageUrls,
                      initialVideoUrl:
                          widget.initialItem?.videoUrls.isNotEmpty == true
                          ? widget.initialItem!.videoUrls.first
                          : null,
                    ),
                    const SizedBox(height: 24),

                    TextFormField(
                      controller: _titleController,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      maxLength: 50,
                      decoration: _inputDecoration('Título del producto'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<MarketCategory>(
                            initialValue: _selectedCategory,
                            dropdownColor: Colors.grey[900],
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration('Categoría'),
                            items: MarketCategory.values.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(cat.displayName),
                              );
                            }).toList(),
                            onChanged: (cat) {
                              if (cat != null) {
                                setState(() => _selectedCategory = cat);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: _inputDecoration('Precio \$ (Ops.)'),
                            validator: (v) {
                              if (v != null &&
                                  v.isNotEmpty &&
                                  double.tryParse(v) == null) {
                                return 'Número inválido';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: Colors.white70),
                      maxLines: 5,
                      decoration: _inputDecoration('Descripción detallada...'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Requerido' : null,
                    ),

                    const SizedBox(height: 16),
                    // SECCIÓN UBICACIÓN
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orangeAccent.withOpacity(0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.orangeAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'REGIÓN Y UBICACIÓN',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed:
                                    _isLocating ? null : _getCurrentLocation,
                                icon: _isLocating
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.orangeAccent,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.my_location,
                                        size: 16,
                                        color: Colors.orangeAccent,
                                      ),
                                label: const Text(
                                  '¡ESTOY AQUÍ!',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRegion,
                            dropdownColor: Colors.grey[900],
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Selecciona una región',
                              hintStyle: TextStyle(color: Colors.white24),
                              border: InputBorder.none,
                            ),
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
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.initialItem != null ? 'ACTUALIZAR' : 'PUBLICAR',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Colors.grey[900],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.orangeAccent),
      ),
    );
  }
}
