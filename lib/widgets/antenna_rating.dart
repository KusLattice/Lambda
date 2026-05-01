import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/rating_provider.dart';
import 'package:lambda_app/services/rating_service.dart';

/// Widget de rating mediante íconos de antena de telecomunicaciones.
/// Exclusivo para Hospedaje (lodging_tracker) y Picás (food_tracker).
///
/// Características:
/// - 5 antenas que "se encienden" con glow animado al seleccionar
/// - El usuario puede cambiar su voto
/// - Muestra el promedio y conteo de votos del post (pasados como parámetro
///   y leídos en tiempo real del stream del post padre)
/// - Al hacer tap, persiste en Firestore vía transacción atómica
class AntennaRating extends ConsumerStatefulWidget {
  final String postId;
  final String collectionName;
  final Color accentColor;

  /// Promedio actual del post (desde el modelo, puede ser 0.0 si nadie votó).
  final double currentAverage;

  /// Cantidad de votos actuales del post.
  final int ratingCount;

  const AntennaRating({
    super.key,
    required this.postId,
    required this.collectionName,
    required this.accentColor,
    this.currentAverage = 0.0,
    this.ratingCount = 0,
  });

  @override
  ConsumerState<AntennaRating> createState() => _AntennaRatingState();
}

class _AntennaRatingState extends ConsumerState<AntennaRating>
    with TickerProviderStateMixin {
  late final List<AnimationController> _glowControllers;
  late final List<Animation<double>> _glowAnimations;
  int? _selectedValue; // voto del usuario actual (null = no votado aún)
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();

    // Un controlador de animación por antena para el efecto glow pulsante
    _glowControllers = List.generate(5, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 800 + i * 80),
      );
      return ctrl;
    });

    _glowAnimations = _glowControllers
        .map(
          (ctrl) => Tween<double>(
            begin: 4.0,
            end: 16.0,
          ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut)),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final ctrl in _glowControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  /// Enciende (anima) las primeras [count] antenas.
  void _activateAntennas(int count) {
    for (int i = 0; i < 5; i++) {
      if (i < count) {
        if (!_glowControllers[i].isAnimating) {
          _glowControllers[i].repeat(reverse: true);
        }
      } else {
        _glowControllers[i].stop();
        _glowControllers[i].reset();
      }
    }
  }

  Future<void> _submitRating(int value, String userId) async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _selectedValue = value;
    });
    _activateAntennas(value);

    try {
      await RatingService.submitRating(
        collectionName: widget.collectionName,
        postId: widget.postId,
        userId: userId,
        value: value,
      );
      // Refrescar el voto del usuario desde Firestore
      ref.invalidate(
        userRatingProvider((
          collectionName: widget.collectionName,
          postId: widget.postId,
          userId: userId,
        )),
      );
    } catch (e) {
      // Revertir estado local si falla
      if (mounted) {
        setState(() => _selectedValue = null);
        _activateAntennas(0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar evaluación: $e'),
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
    final currentUser = ref.watch(authProvider).valueOrNull;

    // Si hay usuario, cargar su voto guardado en Firestore
    if (currentUser != null) {
      final savedRatingAsync = ref.watch(
        userRatingProvider((
          collectionName: widget.collectionName,
          postId: widget.postId,
          userId: currentUser.id,
        )),
      );

      savedRatingAsync.whenData((savedValue) {
        if (savedValue != null && _selectedValue == null) {
          // Primera carga: sincronizar con el valor guardado
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedValue == null) {
              setState(() => _selectedValue = savedValue);
              _activateAntennas(savedValue);
            }
          });
        }
      });
    }

    final effectiveSelected = _selectedValue ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.white10),
        const SizedBox(height: 12),

        // Cabecera
        Row(
          children: [
            Icon(
              Icons.settings_input_antenna,
              color: widget.accentColor,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'SEÑAL DE CALIDAD',
              style: TextStyle(
                color: widget.accentColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                fontFamily: 'Courier',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Las 5 antenas
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(5, (index) {
            final antennaValue = index + 1;
            final isActive = antennaValue <= effectiveSelected;

            return GestureDetector(
              onTap: currentUser == null
                  ? null
                  : () => _submitRating(antennaValue, currentUser.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AnimatedBuilder(
                  animation: _glowAnimations[index],
                  builder: (context, child) {
                    final glowRadius = isActive
                        ? _glowAnimations[index].value
                        : 0.0;
                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: widget.accentColor.withValues(alpha: 0.6),
                                  blurRadius: glowRadius,
                                  spreadRadius: glowRadius * 0.3,
                                ),
                              ]
                            : [],
                      ),
                      child: Icon(
                        Icons.settings_input_antenna,
                        size: 32,
                        color: isActive ? widget.accentColor : Colors.white24,
                      ),
                    );
                  },
                ),
              ),
            );
          }),
          // Spinner si está enviando
        ),

        const SizedBox(height: 10),

        // Promedio y contador
        Row(
          children: [
            if (_isSubmitting)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: widget.accentColor,
                ),
              )
            else if (effectiveSelected > 0)
              Icon(Icons.bolt, color: widget.accentColor, size: 16),
            const SizedBox(width: 4),
            if (widget.currentAverage > 0)
              Text(
                '${widget.currentAverage.toStringAsFixed(1)} / 5.0',
                style: TextStyle(
                  color: widget.accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              )
            else
              Text(
                currentUser == null
                    ? 'Inicia sesión para evaluar'
                    : 'Sé el primero en evaluar',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            if (widget.ratingCount > 0) ...[
              const SizedBox(width: 8),
              Text(
                '· ${widget.ratingCount} ${widget.ratingCount == 1 ? 'evaluación' : 'evaluaciones'}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
