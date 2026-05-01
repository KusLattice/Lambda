import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Módulo flotante arrastrable del dashboard Lambda.
///
/// Fix: usa [GestureDetector] + [onPanUpdate] con deltas locales para que el
/// módulo se quede EXACTAMENTE donde lo soltás, sin saltar a coordenadas globales.
class DraggableModule extends StatefulWidget {
  final String title;
  final Widget child;
  final Offset position;
  final Function(Offset) onDragEnd;
  final bool showBadge;

  const DraggableModule({
    super.key,
    required this.title,
    required this.child,
    required this.position,
    required this.onDragEnd,
    this.showBadge = false,
  });

  @override
  State<DraggableModule> createState() => _DraggableModuleState();
}

class _DraggableModuleState extends State<DraggableModule> {
  late Offset _currentPosition;
  bool _isDragging = false;

  static const double _moduleWidth = 90;
  static const double _moduleHeight = 90;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.position;
  }

  @override
  void didUpdateWidget(covariant DraggableModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sincronizamos la posición si el provider la actualiza externamente (ej: reset).
    if (oldWidget.position != widget.position && !_isDragging) {
      _currentPosition = widget.position;
    }
  }


  late Offset _dragStartPos;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _currentPosition.dx,
      top: _currentPosition.dy,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onLongPressStart: (_) {
              HapticFeedback.heavyImpact();
              setState(() {
                _isDragging = true;
                _dragStartPos = _currentPosition;
              });
            },
            onLongPressMoveUpdate: (details) {
              setState(() {
                _currentPosition = _dragStartPos + details.localOffsetFromOrigin;
              });
            },
            onLongPressEnd: (_) {
              setState(() => _isDragging = false);
              widget.onDragEnd(_currentPosition);
            },
            onLongPressUp: () {
              setState(() => _isDragging = false);
              widget.onDragEnd(_currentPosition);
            },
            child: AnimatedScale(
              scale: _isDragging ? 1.06 : 1.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: Container(
                width: _moduleWidth,
                height: _moduleHeight,
                decoration: BoxDecoration(
                  color: _isDragging
                      ? Colors.greenAccent.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isDragging
                        ? Colors.greenAccent.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.05),
                    width: _isDragging ? 1.5 : 1.0,
                  ),
                  boxShadow: _isDragging
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.withValues(alpha: 0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: widget.child,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 8.0,
                        left: 4.0,
                        right: 4.0,
                      ),
                      child: Text(
                        widget.title.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Courier',
                          fontSize: 10,
                          letterSpacing: 1.0,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.showBadge)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
