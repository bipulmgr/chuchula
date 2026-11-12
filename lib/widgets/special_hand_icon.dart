import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The icon for showing a special hand: a fan of three playing cards with
/// a crown on the front card. Drawn in code so it matches the table's
/// colours at any size.
class SpecialHandIcon extends StatelessWidget {
  const SpecialHandIcon({super.key, this.size = 24, this.color});

  final double size;

  /// Outline and crown colour. Defaults to the ambient icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.white;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SpecialHandPainter(c)),
    );
  }
}

class _SpecialHandPainter extends CustomPainter {
  _SpecialHandPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);

    final cardW = s * 0.42;
    final cardH = s * 0.74;
    final pivot = Offset(s * 0.5, s * 1.3);
    final stroke = math.max(1.0, s * 0.055);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;
    // The back cards are a translucent fill of the same colour, so the
    // icon reads on light and dark backgrounds alike.
    final back = Paint()..color = color.withValues(alpha: 0.32);

    RRect cardAt(double angle) {
      canvas
        ..save()
        ..translate(pivot.dx, pivot.dy)
        ..rotate(angle)
        ..translate(-pivot.dx, -pivot.dy);
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(
          pivot.dx - cardW / 2,
          pivot.dy - cardH - s * 0.42,
          cardW,
          cardH,
        ),
        Radius.circular(s * 0.07),
      );
    }

    // Two cards behind, fanned left and right.
    for (final angle in const [-0.24, 0.24]) {
      final r = cardAt(angle);
      canvas
        ..drawRRect(r, back)
        ..drawRRect(r, outline)
        ..restore();
    }

    // The front card with a crown.
    final front = cardAt(0);
    canvas
      ..drawRRect(front, Paint()..color = color)
      ..drawRRect(front, outline);
    final b = front.outerRect;
    final cw = b.width * 0.66;
    final ch = b.height * 0.36;
    final left = b.center.dx - cw / 2;
    final top = b.center.dy - ch / 2;
    final crown = Path()
      ..moveTo(left, top + ch)
      ..lineTo(left, top + ch * 0.2)
      ..lineTo(left + cw * 0.27, top + ch * 0.58)
      ..lineTo(left + cw * 0.5, top)
      ..lineTo(left + cw * 0.73, top + ch * 0.58)
      ..lineTo(left + cw, top + ch * 0.2)
      ..lineTo(left + cw, top + ch)
      ..close();
    // The crown is a contrasting tone of the same colour on the card face.
    final dark = color.computeLuminance() < 0.3;
    final crownColor = Color.lerp(
      color,
      dark ? Colors.white : Colors.black,
      0.7,
    )!;
    canvas
      ..drawPath(crown, Paint()..color = crownColor)
      ..restore();
  }

  @override
  bool shouldRepaint(_SpecialHandPainter old) => old.color != color;
}
