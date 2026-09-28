import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Open book on a peach wash with a morning sun, drawn in code so it
/// scales cleanly and needs no image asset.
class ReminderIllustration extends StatelessWidget {
  const ReminderIllustration({super.key, this.size = 220});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size * 0.72),
        painter: _BookSunPainter(),
      ),
    );
  }
}

class _BookSunPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;

    // Peach wash
    final wash = Paint()..color = AppColors.peach;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.62), width: w * 0.9, height: h * 0.62),
      wash,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.3, h * 0.5), width: w * 0.45, height: h * 0.45),
      wash,
    );

    // Sun + rays
    final sunCenter = Offset(w * 0.5, h * 0.16);
    final sunR = w * 0.07;
    canvas.drawCircle(
        sunCenter, sunR, Paint()..color = const Color(0xFFF7A868));
    final ray = Paint()
      ..color = const Color(0xFFF7A868)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 9; i++) {
      final a = math.pi + (math.pi / 8) * i;
      canvas.drawLine(
        sunCenter + Offset(math.cos(a), math.sin(a)) * (sunR + 5),
        sunCenter + Offset(math.cos(a), math.sin(a)) * (sunR + 13),
        ray,
      );
    }

    // Leaves
    _leaf(canvas, Offset(w * 0.12, h * 0.42), -0.5, w * 0.1,
        const Color(0xFFB9C4A6));
    _leaf(canvas, Offset(w * 0.9, h * 0.38), 0.6, w * 0.1,
        const Color(0xFFB9C4A6));
    _leaf(canvas, Offset(w * 0.8, h * 0.2), 0.2, w * 0.05, AppColors.orange);

    // Book
    final spine = Offset(w * 0.5, h * 0.5);
    final bookW = w * 0.36;
    final pageTop = h * 0.3;
    final pageBottom = h * 0.82;
    final shadow = Paint()..color = const Color(0x22A0522D);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, pageBottom + 6),
          width: bookW * 2.1,
          height: 14),
      shadow,
    );

    final cover = Paint()..color = const Color(0xFFD98B55);
    final coverPath = Path()
      ..moveTo(spine.dx, pageBottom + 4)
      ..quadraticBezierTo(spine.dx - bookW * 0.5, pageBottom - 6,
          spine.dx - bookW - 6, pageBottom + 2)
      ..lineTo(spine.dx - bookW - 6, pageTop + 8)
      ..lineTo(spine.dx + bookW + 6, pageTop + 8)
      ..lineTo(spine.dx + bookW + 6, pageBottom + 2)
      ..quadraticBezierTo(
          spine.dx + bookW * 0.5, pageBottom - 6, spine.dx, pageBottom + 4)
      ..close();
    canvas.drawPath(coverPath, cover);

    final page = Paint()..color = const Color(0xFFFFFBF6);
    final edge = Paint()
      ..color = const Color(0xFFE2C9B3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final dir in [-1.0, 1.0]) {
      final p = Path()
        ..moveTo(spine.dx, pageTop + 10)
        ..quadraticBezierTo(spine.dx + dir * bookW * 0.5, pageTop - 8,
            spine.dx + dir * bookW, pageTop)
        ..lineTo(spine.dx + dir * bookW, pageBottom - 6)
        ..quadraticBezierTo(
            spine.dx + dir * bookW * 0.5, pageBottom - 14, spine.dx, pageBottom)
        ..close();
      canvas.drawPath(p, page);
      canvas.drawPath(p, edge);

      // Text lines
      final line = Paint()
        ..color = const Color(0xFFE8D6C6)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 7; i++) {
        final y = pageTop + 14 + i * ((pageBottom - pageTop - 30) / 7);
        final x1 = spine.dx + dir * 10;
        final x2 = spine.dx + dir * (bookW - 10);
        canvas.drawLine(Offset(x1, y + 3), Offset(x2, y), line);
      }
    }
    canvas.drawLine(
      Offset(spine.dx, pageTop + 10),
      Offset(spine.dx, pageBottom),
      edge,
    );
  }

  void _leaf(Canvas c, Offset at, double angle, double len, Color color) {
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(angle);
    final p = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(len * 0.5, -len * 0.35, len, 0)
      ..quadraticBezierTo(len * 0.5, len * 0.35, 0, 0)
      ..close();
    c.drawPath(p, Paint()..color = color);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
