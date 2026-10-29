import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/table_themes.dart';
import '../game/models/card.dart';

const double kCardAspect = 0.7; // width / height

const _red = Color(0xFFC0262D);
const _black = Color(0xFF1B1B22);

Color suitColor(Suit s) => s.isRed ? _red : _black;

/// Vector suit symbol, so suits render crisply at any size without relying
/// on font glyph coverage.
class SuitIcon extends StatelessWidget {
  const SuitIcon(this.suit, {super.key, required this.size, this.color});

  final Suit suit;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SuitPainter(suit, color ?? suitColor(suit)),
  );
}

class _SuitPainter extends CustomPainter {
  _SuitPainter(this.suit, this.color);

  final Suit suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      suitPath(suit, size.width),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SuitPainter old) =>
      old.suit != suit || old.color != color;
}

Path suitPath(Suit suit, double s) {
  final p = Path();
  switch (suit) {
    case Suit.hearts:
      p.moveTo(s * 0.5, s * 0.92);
      p.cubicTo(s * 0.12, s * 0.62, s * -0.02, s * 0.38, s * 0.18, s * 0.16);
      p.cubicTo(s * 0.34, s * 0.0, s * 0.48, s * 0.1, s * 0.5, s * 0.26);
      p.cubicTo(s * 0.52, s * 0.1, s * 0.66, s * 0.0, s * 0.82, s * 0.16);
      p.cubicTo(s * 1.02, s * 0.38, s * 0.88, s * 0.62, s * 0.5, s * 0.92);
    case Suit.diamonds:
      p.moveTo(s * 0.5, s * 0.02);
      p.quadraticBezierTo(s * 0.7, s * 0.3, s * 0.9, s * 0.5);
      p.quadraticBezierTo(s * 0.7, s * 0.7, s * 0.5, s * 0.98);
      p.quadraticBezierTo(s * 0.3, s * 0.7, s * 0.1, s * 0.5);
      p.quadraticBezierTo(s * 0.3, s * 0.3, s * 0.5, s * 0.02);
    case Suit.spades:
      p.moveTo(s * 0.5, s * 0.04);
      p.cubicTo(s * 0.86, s * 0.36, s * 1.02, s * 0.52, s * 0.86, s * 0.7);
      p.cubicTo(s * 0.74, s * 0.82, s * 0.58, s * 0.76, s * 0.53, s * 0.66);
      p.quadraticBezierTo(s * 0.56, s * 0.86, s * 0.7, s * 0.96);
      p.lineTo(s * 0.3, s * 0.96);
      p.quadraticBezierTo(s * 0.44, s * 0.86, s * 0.47, s * 0.66);
      p.cubicTo(s * 0.42, s * 0.76, s * 0.26, s * 0.82, s * 0.14, s * 0.7);
      p.cubicTo(s * -0.02, s * 0.52, s * 0.14, s * 0.36, s * 0.5, s * 0.04);
    case Suit.clubs:
      p.addOval(
        Rect.fromCircle(center: Offset(s * 0.5, s * 0.27), radius: s * 0.2),
      );
      p.addOval(
        Rect.fromCircle(center: Offset(s * 0.27, s * 0.56), radius: s * 0.2),
      );
      p.addOval(
        Rect.fromCircle(center: Offset(s * 0.73, s * 0.56), radius: s * 0.2),
      );
      p.moveTo(s * 0.46, s * 0.5);
      p.quadraticBezierTo(s * 0.46, s * 0.84, s * 0.3, s * 0.96);
      p.lineTo(s * 0.7, s * 0.96);
      p.quadraticBezierTo(s * 0.54, s * 0.84, s * 0.54, s * 0.5);
      p.close();
  }
  return p;
}

/// A face-up playing card.
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    required this.width,
    this.highlight,
    this.dimmed = false,
    this.elevation = 2,
  });

  final PlayingCard card;
  final double width;
  final Color? highlight;
  final bool dimmed;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final h = width / kCardAspect;
    final color = suitColor(card.suit);
    final indexSize = width * 0.30;
    final isFace =
        card.rank == Rank.jack ||
        card.rank == Rank.queen ||
        card.rank == Rank.king;
    return Semantics(
      label: '${card.rank.label} ${card.suit.name}',
      child: Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.1),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFDF6), Color(0xFFF3EBD6)],
          ),
          border: Border.all(
            color: highlight ?? const Color(0xFFCDBB8A),
            width: highlight != null ? 2.2 : 0.8,
          ),
          boxShadow: [
            if (highlight != null)
              BoxShadow(
                color: highlight!.withValues(alpha: 0.7),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: elevation * 2,
              offset: Offset(0, elevation),
            ),
          ],
        ),
        foregroundDecoration: dimmed
            ? BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(width * 0.1),
              )
            : null,
        child: Stack(
          children: [
            Positioned(
              left: width * 0.06,
              top: width * 0.04,
              child: _CornerIndex(card, indexSize, color),
            ),
            Positioned(
              right: width * 0.06,
              bottom: width * 0.04,
              child: Transform.rotate(
                angle: math.pi,
                child: _CornerIndex(card, indexSize * 0.8, color),
              ),
            ),
            Align(
              alignment: const Alignment(0.25, 0.25),
              child: isFace
                  ? _FaceCourt(card: card, width: width, color: color)
                  : SuitIcon(card.suit, size: width * 0.42),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerIndex extends StatelessWidget {
  const _CornerIndex(this.card, this.size, this.color);

  final PlayingCard card;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = card.rank.label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Mukta',
            fontWeight: FontWeight.w800,
            fontSize: label.length > 1 ? size * 0.82 : size,
            height: 1.0,
            color: color,
            letterSpacing: label.length > 1 ? -1.5 : 0,
          ),
        ),
        SizedBox(height: size * 0.06),
        SuitIcon(card.suit, size: size * 0.7, color: color),
      ],
    );
  }
}

/// Court cards: an ornamental frame with the rank letter, drawn rather than
/// using artwork so it stays crisp and original.
class _FaceCourt extends StatelessWidget {
  const _FaceCourt({
    required this.card,
    required this.width,
    required this.color,
  });

  final PlayingCard card;
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = width * 0.5;
    return Container(
      width: s,
      height: s * 1.3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s * 0.18),
        border: Border.all(color: const Color(0xFFC9A54A), width: 1.4),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.10),
            const Color(0xFFE9C766).withValues(alpha: 0.25),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (card.rank) {
              Rank.king => Icons.workspace_premium,
              Rank.queen => Icons.local_florist,
              _ => Icons.shield_moon,
            },
            size: s * 0.38,
            color: const Color(0xFFB08A2E),
          ),
          Text(
            card.rank.label,
            style: TextStyle(
              fontFamily: 'YatraOne',
              fontSize: s * 0.5,
              height: 1.0,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A face-down card using the selected back design.
class CardBack extends StatelessWidget {
  const CardBack({
    super.key,
    required this.width,
    required this.style,
    required this.theme,
    this.elevation = 2,
  });

  final double width;
  final CardBackId style;
  final TableTheme theme;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final h = width / kCardAspect;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.1),
        color: const Color(0xFFFFF8E6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: elevation * 2,
            offset: Offset(0, elevation),
          ),
        ],
      ),
      padding: EdgeInsets.all(width * 0.06),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.07),
        child: CustomPaint(painter: CardBackPainter(style, theme)),
      ),
    );
  }
}

class CardBackPainter extends CustomPainter {
  CardBackPainter(this.style, this.theme);

  final CardBackId style;
  final TableTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    switch (style) {
      case CardBackId.dhaka:
        _dhaka(canvas, size);
      case CardBackId.mandala:
        _mandala(canvas, size);
      case CardBackId.lotus:
        _lotus(canvas, size);
      case CardBackId.classic:
        _classic(canvas, size);
    }
    canvas.drawRect(
      rect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = theme.accent,
    );
  }

  /// Geometric pattern inspired by Nepali Dhaka weaving.
  void _dhaka(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF8C1C24),
    );
    final cell = size.width / 4;
    final colors = [
      const Color(0xFF1C1C1C),
      const Color(0xFFF2E6C9),
      theme.accent,
    ];
    var k = 0;
    for (double y = -cell / 2; y < size.height + cell; y += cell / 2) {
      final offset = (k.isEven ? 0.0 : cell / 2);
      for (double x = -cell; x < size.width + cell; x += cell) {
        final cx = x + offset;
        final p = Path()
          ..moveTo(cx, y - cell / 4)
          ..lineTo(cx + cell / 4, y)
          ..lineTo(cx, y + cell / 4)
          ..lineTo(cx - cell / 4, y)
          ..close();
        canvas.drawPath(p, Paint()..color = colors[k % 3]);
        canvas.drawCircle(
          Offset(cx, y),
          cell * 0.06,
          Paint()..color = const Color(0xFF8C1C24),
        );
      }
      k++;
    }
  }

  void _mandala(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color.lerp(theme.feltEdge, Colors.black, 0.2)!,
    );
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = theme.accent;
    for (
      var r = size.width * 0.08;
      r < size.width * 0.48;
      r += size.width * 0.1
    ) {
      canvas.drawCircle(c, r, stroke);
    }
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      final petal = Path()
        ..moveTo(c.dx, c.dy)
        ..quadraticBezierTo(
          c.dx + math.cos(a + 0.25) * size.width * 0.3,
          c.dy + math.sin(a + 0.25) * size.width * 0.3,
          c.dx + math.cos(a) * size.width * 0.44,
          c.dy + math.sin(a) * size.width * 0.44,
        );
      canvas.drawPath(petal, stroke);
    }
    canvas.drawCircle(c, size.width * 0.05, Paint()..color = theme.accent);
  }

  void _lotus(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1E3A5F),
    );
    final fill = Paint()
      ..color = const Color(0xFFE88FA8).withValues(alpha: 0.9);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = theme.accentSoft;
    final c = Offset(size.width / 2, size.height * 0.56);
    final w = size.width * 0.4;
    for (var i = -2; i <= 2; i++) {
      final a = i * 0.42;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      final petal = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(w * 0.35, -w * 0.5, 0, -w * 1.05)
        ..quadraticBezierTo(-w * 0.35, -w * 0.5, 0, 0);
      canvas.drawPath(petal, fill);
      canvas.drawPath(petal, line);
      canvas.restore();
    }
    for (
      double y = size.height * 0.68;
      y < size.height;
      y += size.height * 0.06
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  void _classic(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF14365A),
    );
    final line = Paint()
      ..strokeWidth = 1
      ..color = theme.accent.withValues(alpha: 0.75);
    final step = size.width / 7;
    for (double i = -size.height; i < size.width + size.height; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), line);
      canvas.drawLine(Offset(i, size.height), Offset(i + size.height, 0), line);
    }
  }

  @override
  bool shouldRepaint(CardBackPainter old) =>
      old.style != style || old.theme.id != theme.id;
}
