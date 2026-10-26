import 'package:flutter/material.dart';

import '../../core/theme/table_themes.dart';
import '../../widgets/card_widgets.dart';

const _targets = [
  Alignment(0, 1.05),
  Alignment(1.05, 0),
  Alignment(0, -1.05),
  Alignment(-1.05, 0),
];

/// Cards fly from the deck in the middle of the table to every seat, one at
/// a time starting left of the dealer. Purely visual: the engine has
/// already dealt; this only plays when a new round starts.
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
          final w = (c.maxWidth / 9).clamp(28.0, 52.0);
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value;
              if (t <= 0 || t >= 1) return const SizedBox.shrink();
              final children = <Widget>[];
              // Remaining deck in the middle.
              final dealt = (t * 52 * 1.15).floor().clamp(0, 52);
              if (dealt < 52) {
                children.add(
                  Align(
                    child: CardBack(width: w, style: cardBack, theme: theme),
                  ),
                );
              }
              for (var i = 0; i < 52; i++) {
                // Each card flies during its own window.
                final start = i / 52 * 0.85;
                final local = ((t - start) / 0.15).clamp(0.0, 1.0);
                if (local <= 0 || local >= 1) continue;
                final pos = (firstPosition + i) % 4;
                final eased = Curves.easeOutCubic.transform(local);
                children.add(
                  Align(
                    alignment: Alignment.lerp(
                      Alignment.center,
                      _targets[pos],
                      eased,
                    )!,
                    child: Transform.rotate(
                      angle: (1 - eased) * 0.8 * (i.isEven ? 1 : -1),
                      child: Opacity(
                        opacity: 1 - eased * 0.6,
                        child: CardBack(
                          width: w * (1 - 0.25 * eased),
                          style: cardBack,
                          theme: theme,
                          elevation: 6,
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Stack(children: children);
            },
          );
        },
      ),
    );
  }
}
