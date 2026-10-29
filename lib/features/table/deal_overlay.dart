import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/table_themes.dart';
import '../../widgets/card_widgets.dart';

/// Where each relative position (0 bottom, 1 right, 2 top, 3 left) receives
/// its cards, matching the seat plates on the table.
const _targets = [
  Alignment(0, 1.25),
  Alignment(0.92, -0.25),
  Alignment(0, -0.92),
  Alignment(-0.92, -0.25),
];

/// Final card angle at each position, so cards arrive facing the player.
const _angles = [0.0, math.pi / 2, 0.0, -math.pi / 2];

/// Timing of the deal over the controller's 0..1: a short shuffle, then
/// the 52 cards leave the deck at an even rhythm, one per seat in turn.
class DealTiming {
  const DealTiming._();

  static const int cards = 52;

  /// The deck is riffled until this point.
  static const double shuffleEnd = 0.16;

  /// How long one card is in the air.
  static const double flight = 0.12;

  static const double _step = (1 - shuffleEnd - flight) / (cards - 1);

  static double start(int i) => shuffleEnd + i * _step;

  /// 0..1 progress of card [i] through its flight.
  static double local(int i, double t) =>
      ((t - start(i)) / flight).clamp(0.0, 1.0);

  /// How many cards have left the deck at [t].
  static int dealtCount(double t) {
    if (t < shuffleEnd) return 0;
    return (((t - shuffleEnd) / _step).floor() + 1).clamp(0, cards);
  }

  /// How many cards have landed at relative position 0 (the local player)
  /// when [firstPosition] is dealt first.
  static int landedAtBottom(double t, int firstPosition) {
    var n = 0;
    for (var i = 0; i < cards; i++) {
      if ((firstPosition + i) % 4 == 0 && local(i, t) >= 1) n++;
    }
    return n;
  }
}

/// Cards are riffled, then fly from the deck in the middle of the table to
/// every seat in a gentle arc, one at a time starting left of the dealer.
/// Purely visual: the engine has already dealt; this only plays when a new
/// round starts.
class DealOverlay extends StatelessWidget {
  const DealOverlay({
    super.key,
    required this.animation,
    required this.firstPosition,
    required this.theme,
    required this.cardBack,
  });

  /// 0..1 over the whole deal.
  final Animation<double> animation;

  /// Relative position (0 bottom, 1 right, 2 top, 3 left) dealt first.
  final int firstPosition;
  final TableTheme theme;
  final CardBackId cardBack;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final w = (c.maxWidth / 8).clamp(30.0, 58.0);
          final h = w / kCardAspect;
          final back = RepaintBoundary(
            child: CardBack(width: w, style: cardBack, theme: theme),
          );
          final flying = RepaintBoundary(
            child: CardBack(
              width: w,
              style: cardBack,
              theme: theme,
              elevation: 7,
            ),
          );
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value;
              if (t <= 0 || t >= 1) return const SizedBox.shrink();
              final center = size.center(Offset.zero);
              Widget at(Offset o, Widget child, {double angle = 0}) =>
                  Positioned(
                    left: o.dx - w / 2,
                    top: o.dy - h / 2,
                    width: w,
                    height: h,
                    child: Transform.rotate(angle: angle, child: child),
                  );
              final children = <Widget>[];

              // The deck: a short stack that thins out as cards leave it.
              final remaining = DealTiming.cards - DealTiming.dealtCount(t);
              if (t < DealTiming.shuffleEnd) {
                // Riffle: the two halves part, then interleave, twice.
                final p = t / DealTiming.shuffleEnd;
                final spread = math.sin(p * 2 * math.pi).abs() * w * 0.55;
                final tilt = math.sin(p * 2 * math.pi).abs() * 0.12;
                for (var k = 0; k < 3; k++) {
                  final lift = Offset(0, -k * 1.2);
                  children
                    ..add(
                      at(center + lift - Offset(spread, 0), back, angle: -tilt),
                    )
                    ..add(
                      at(center + lift + Offset(spread, 0), back, angle: tilt),
                    );
                }
              } else if (remaining > 0) {
                final layers = (remaining / 9).ceil().clamp(1, 6);
                for (var k = 0; k < layers; k++) {
                  children.add(at(center + Offset(0, -k * 1.2), back));
                }
              }

              // Cards in the air.
              for (var i = 0; i < DealTiming.cards; i++) {
                final local = DealTiming.local(i, t);
                if (local <= 0 || local >= 1) continue;
                final pos = (firstPosition + i) % 4;
                final e = Curves.easeOutCubic.transform(local);
                final target = _targets[pos].alongSize(size);
                // A quadratic arc: the control point sits off the straight
                // line, alternating sides so the stream looks natural.
                final mid = Offset.lerp(center, target, 0.5)!;
                final d = target - center;
                final normal = d.distance == 0
                    ? Offset.zero
                    : Offset(-d.dy, d.dx) / d.distance;
                final control =
                    mid + normal * (d.distance * 0.12 * (i.isEven ? 1 : -1));
                final p = _quad(center, control, target, e);
                final spin = (i.isEven ? 1 : -1) * 0.5 * math.sin(e * math.pi);
                final scale = pos == 0 ? 1 + 0.2 * e : 1 - 0.25 * e;
                final fade = local < 0.8 ? 1.0 : (1 - local) / 0.2;
                children.add(
                  at(
                    p,
                    Opacity(
                      opacity: fade,
                      child: Transform.scale(scale: scale, child: flying),
                    ),
                    angle: _angles[pos] * e + spin,
                  ),
                );
              }
              return Stack(clipBehavior: Clip.none, children: children);
            },
          );
        },
      ),
    );
  }

  static Offset _quad(Offset a, Offset b, Offset c, double t) {
    final u = 1 - t;
    return a * (u * u) + b * (2 * u * t) + c * (t * t);
  }
}
