import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lambda_app/models/fiber_cut_report.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/fiber_cut_provider.dart';
import 'package:lambda_app/services/geocoding_service.dart';
import 'package:lambda_app/widgets/media_selector_field.dart';
import 'package:lambda_app/config/app_config.dart';
import 'package:geocoding/geocoding.dart' as native_geocoding;
import 'package:lambda_app/config/chile_regions.dart';

class CreateFiberCutScreen extends ConsumerStatefulWidget {
  static const String routeName = '/create-fiber-cut';
  final FiberCutReport? initialReport;
  const CreateFiberCutScreen({super.key, this.initialReport});

  @override
  ConsumerState<CreateFiberCutScreen> createState() =>
      _CreateFiberCutScreenState();
}

class _CreateFiberCutScreenState extends ConsumerState<CreateFiberCutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  List<File> _selectedImages = [];
  File? _selectedVideo;
  bool _isSubmitting = false;
  bool _isGettingLocation = false;
  String? _selectedRegion;
  String? _selectedComuna;

  final _geocoding = GeocodingService(apiKey: AppConfig.mapsApiKey);

  void _onMediaChanged(List<File> images, File? video) {
    setState(() {
      _selectedImages = images;
      _selectedVideo = video;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialReport != null) {
      final rep = widget.initialReport!;
      _descriptionController.text = rep.description ?? '';
      _addressController.text = rep.address ?? '';
      _latController.text = rep.location.latitude.toString();
      _lngController.text = rep.location.longitude.toString();
      _selectedRegion = rep.region;
      _selectedComuna = rep.comuna;
    }
  }

  Future<void> _updateCoordsFromAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) return;

    try {
      List<native_geocoding.Location> locations = await native_geocoding
          .locationFromAddress(address);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        setState(() {
          _latController.text = loc.latitude.toString();
          _lngController.text = loc.longitude.toString();
        });

        List<native_geocoding.Placemark> placemarks = await native_geocoding
            .placemarkFromCoordinates(loc.latitude, loc.longitude);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final normalizedReg = matchChileRegion(place.administrativeArea);
          if (normalizedReg != null) {
            setState(() {
              _selectedRegion = normalizedReg;
              final comunas = kChileRegions[normalizedReg] ?? [];
              final matchComuna = comunas.firstWhere(
                (c) =>
                    c.toLowerCase() == place.locality?.toLowerCase() ||
                    c.toLowerCase() == place.subLocality?.toLowerCase(),
                orElse: () => '',
              );
              if (matchComuna.isNotEmpty) _selectedComuna = matchComuna;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
  }

  Future<void> _updateAddressFromCoords() async {
    final latText = _latController.text.trim();
    final lngText = _lngController.text.trim();
    if (latText.isEmpty || lngText.isEmpty) return;

    try {
      final lat = double.tryParse(latText);
      final lon = double.tryParse(lngText);
      if (lat != null && lon != null) {
        final geoResult = await _geocoding.reverseGeocode(lat, lon);
        if (geoResult != null && geoResult.formattedAddress != null) {
          List<native_geocoding.Placemark> placemarks = await native_geocoding
              .placemarkFromCoordinates(lat, lon);

          setState(() {
            _addressController.text = geoResult.formattedAddress!;
            if (placemarks.isNotEmpty) {
              final place = placemarks.first;
              final normalizedReg = matchChileRegion(place.administrativeArea);
              if (normalizedReg != null) {
                _selectedRegion = normalizedReg;
                final comunas = kChileRegions[normalizedReg] ?? [];
                final matchComuna = comunas.firstWhere(
                  (c) =>
                      c.toLowerCase() == place.locality?.toLowerCase() ||
                      c.toLowerCase() == place.subLocality?.toLowerCase(),
                  orElse: () => '',
                );
                if (matchComuna.isNotEmpty) _selectedComuna = matchComuna;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
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

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final geoResult = await _geocoding.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );

      List<native_geocoding.Placemark> placemarks = await native_geocoding
          .placemarkFromCoordinates(pos.latitude, pos.longitude);

      setState(() {
        _latController.text = pos.latitude.toString();
        _lngController.text = pos.longitude.toString();
        _addressController.text = geoResult?.formattedAddress ?? '';

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final normalizedReg = matchChileRegion(place.administrativeArea);
          if (normalizedReg != null) {
            _selectedRegion = normalizedReg;
            // Forzar actualización de comunas
            final comunas = kChileRegions[normalizedReg] ?? [];
            final matchComuna = comunas.firstWhere(
              (c) =>
                  c.toLowerCase() == place.locality?.toLowerCase() ||
                  c.toLowerCase() == place.subLocality?.toLowerCase(),
              orElse: () => '',
            );
            _selectedComuna = matchComuna.isNotEmpty ? matchComuna : null;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ERROR GPS: $e'), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (_latController.text.isEmpty || _lngController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('DEBES CAPTURAR TU UBICACIÓN (ESTOY AQUÍ)'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = ref.read(authProvider).valueOrNull;
      if (user == null) return;

      final double? latitude = double.tryParse(_latController.text);
      final double? longitude = double.tryParse(_lngController.text);

      if (latitude == null || longitude == null) {
        throw Exception('Coordenadas inválidas');
      }

      if (widget.initialReport != null) {
        await ref.read(fiberCutServiceProvider).updateReport(
          widget.initialReport!.id,
          {
            'description': _descriptionController.text.trim(),
            'address': _addressController.text.trim(),
            'location': {'latitude': latitude, 'longitude': longitude},
            'region': _selectedRegion,
            'comuna': _selectedComuna,
          },
        );
      } else {
        await ref
            .read(fiberCutServiceProvider)
            .createReport(
              reporterId: user.id,
              reporterNickname: user.apodo?.isNotEmpty == true
                  ? user.apodo!
                  : user.nombre,
              reporterFotoUrl: user.fotoUrl,
              latitude: latitude,
              longitude: longitude,
              address: _addressController.text.trim(),
              imageFiles: _selectedImages,
              videoFile: _selectedVideo,
              description: _descriptionController.text.trim(),
              region: _selectedRegion,
              comuna: _selectedComuna,
            );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.initialReport != null
                  ? 'REPORTE ACTUALIZADO.'
                  : 'REPORTE ENVIADO CON ÉXITO.',
            ),
            backgroundColor: Colors.green,
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('FALLAS', style: TextStyle(fontFamily: 'Courier')),
        backgroundColor: Colors.black,
        foregroundColor: Colors.redAccent,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(
              widget.initialReport != null
                  ? 'EDITAR REPORTE'
                  : 'REPORTE DE FALLA EN TERRENO',
              style: const TextStyle(
                color: Colors.redAccent,
                fontFamily: 'Courier',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            MediaSelectorField(
              onMediaChanged: _onMediaChanged,
              accentColor: Colors.redAccent,
              initialImages:
                  const [], // TODO: handle existing media edit if needed
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _addressController,
                    onEditingComplete: _updateCoordsFromAddress,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'DIRECCIÓN',
                      labelStyle: TextStyle(color: Colors.redAccent),
                      prefixIcon: Icon(
                        Icons.location_on_outlined,
                        color: Colors.redAccent,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                  const Divider(color: Colors.white10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller:
                              _latController, // Solo mostramos Lat en este campo compacto
                          onEditingComplete: _updateAddressFromCoords,
                          readOnly: true,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'COORDENADAS',
                            labelStyle: TextStyle(color: Colors.redAccent),
                            prefixIcon: Icon(
                              Icons.gps_fixed,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _latController.text.isNotEmpty
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _isGettingLocation
                              ? null
                              : _getCurrentLocation,
                          icon: _isGettingLocation
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.my_location, size: 18),
                          label: Text(
                            _latController.text.isNotEmpty ? 'OK' : 'AQUÍ',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _selectedRegion,
              decoration: InputDecoration(
                labelText: 'REGIÓN',
                labelStyle: const TextStyle(color: Colors.redAccent),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              dropdownColor: const Color(0xFF1A1A1A),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: kRegionNames
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (val) => setState(() {
                _selectedRegion = val;
                _selectedComuna = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_selectedRegion != null)
              DropdownButtonFormField<String>(
                initialValue: _selectedComuna,
                decoration: InputDecoration(
                  labelText: 'COMUNA',
                  labelStyle: const TextStyle(color: Colors.redAccent),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: (kChileRegions[_selectedRegion] ?? [])
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedComuna = val),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'NOTAS ADICIONALES (Opcional)',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.black)
                  : Text(
                      widget.initialReport != null
                          ? 'ACTUALIZAR REPORTE'
                          : 'PUBLICAR REPORTE',
                      style: const TextStyle(
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
    _descriptionController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }
}
