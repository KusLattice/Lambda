import 'package:flutter/material.dart';

/// Canvas de fondo con grid estilo terminal/hacker para el Dashboard.
class GridBackgroundPainter extends CustomPainter {
  const GridBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cellSize = 32.0;
    final paint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.05)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Líneas verticales
    for (double x = 0; x <= size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Líneas horizontales
    for (double y = 0; y <= size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Puntos en las intersecciones (sutil)
    final dotPaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    for (double x = 0; x <= size.width; x += cellSize) {
      for (double y = 0; y <= size.height; y += cellSize) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Widget que envuelve el canvas del dashboard con el grid de fondo.
class GridBackground extends StatelessWidget {
  final Widget child;

  const GridBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: const GridBackgroundPainter(), child: child);
  }
}
