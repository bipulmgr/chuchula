import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/game_state.dart';
import '../../game/models/player_view.dart';
import '../../game/scoring/cash_points.dart';
import '../../widgets/card_widgets.dart';
import '../../widgets/ornaments.dart';

class MatchOverPanel extends StatelessWidget {
  const MatchOverPanel({
    super.key,
    required this.view,
    required this.theme,
    required this.reducedMotion,
    required this.onHome,
    this.onPlayAgain,
    this.onPointsTable,
    this.cashBalance,
  });

  final PlayerView view;
  final TableTheme theme;
  final bool reducedMotion;
  final VoidCallback onHome;
  final VoidCallback? onPlayAgain;
  final VoidCallback? onPointsTable;

  /// The player's cash points after this match was settled, or null when
  /// the match had no stakes.
  final int? cashBalance;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final result = view.result!;
    final iWon = result.winnerSeat == view.mySeat;
    final winnerName = view.seats[result.winnerSeat].name;
    final places = CashPoints.places(result);
    final order = List.generate(kSeatCount, (i) => i)
      ..sort((a, b) => places[a].compareTo(places[b]));
    final cash = cashBalance == null ? null : CashPoints.settle(result);
    final instant = result.reason == MatchEndReason.instantWin;
    final hand = view.lastRound?.instantWinHand;

    return Stack(
      children: [
        if (iWon && !reducedMotion) const Positioned.fill(child: Confetti()),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: GoldPanel(
                theme: theme,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      iWon ? Icons.emoji_events : Icons.sentiment_neutral,
                      size: 64,
                      color: iWon ? theme.glow : theme.accentSoft,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      iWon ? l.matchWon : l.matchLost(winnerName),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'YatraOne',
                        fontSize: 26,
                        color: theme.accent,
                      ),
                    ),
                    if (instant) ...[
                      const SizedBox(height: 6),
                      Text(
                        l.instantWin,
                        style: TextStyle(color: theme.onSurface),
                      ),
                      if (hand != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 2,
                          runSpacing: 4,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final c in hand) CardFace(card: c, width: 28),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 14),
                    for (var i = 0; i < order.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${places[order[i]]}.',
                                style: TextStyle(color: theme.accentSoft),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                view.seats[order[i]].name,
                                style: TextStyle(
                                  fontWeight: order[i] == result.winnerSeat
                                      ? FontWeight.w800
                                      : FontWeight.w400,
                                  color: theme.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              l.pointsShort(view.scores[order[i]]),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: theme.accent,
                              ),
                            ),
                            if (cash != null)
                              SizedBox(
                                width: 56,
                                child: Text(
                                  cash[order[i]] > 0
                                      ? '+${cash[order[i]]}'
                                      : '${cash[order[i]]}',
                                  key: Key('cash-${order[i]}'),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: cash[order[i]] > 0
                                        ? theme.glow
                                        : const Color(0xFFFF9A8A),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (cashBalance != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        l.cashBalance(cashBalance!),
                        key: const Key('cashBalance'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: theme.accentSoft,
                        ),
                      ),
                    ],
                    if (onPointsTable != null)
                      TextButton.icon(
                        key: const Key('matchPointsTable'),
                        onPressed: onPointsTable,
                        icon: Icon(Icons.leaderboard, color: theme.accentSoft),
                        label: Text(
                          l.pointsTable,
                          style: TextStyle(color: theme.accentSoft),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (onPlayAgain != null) ...[
                      GoldButton(
                        theme: theme,
                        label: l.playAgain,
                        icon: Icons.replay,
                        onPressed: onPlayAgain,
                      ),
                      const SizedBox(height: 10),
                    ],
                    GoldButton(
                      theme: theme,
                      label: l.home,
                      icon: Icons.home,
                      primary: false,
                      onPressed: onHome,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lightweight celebration: falling marigold petals and gold flakes.
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..forward();

  final _rnd = math.Random(3);
  late final List<_Flake> _flakes = List.generate(
    70,
    (_) => _Flake(
      x: _rnd.nextDouble(),
      delay: _rnd.nextDouble() * 0.4,
      speed: 0.5 + _rnd.nextDouble() * 0.6,
      sway: _rnd.nextDouble() * 2 * math.pi,
      size: 4 + _rnd.nextDouble() * 6,
      color: [
        const Color(0xFFFFB627),
        const Color(0xFFFF8C1A),
        const Color(0xFFFFE08A),
        const Color(0xFFE63946),
      ][_rnd.nextInt(4)],
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) =>
          CustomPaint(painter: _ConfettiPainter(_flakes, _c.value)),
    ),
  );
}

class _Flake {
  _Flake({
    required this.x,
    required this.delay,
    required this.speed,
    required this.sway,
    required this.size,
    required this.color,
  });
  final double x, delay, speed, sway, size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.flakes, this.t);
  final List<_Flake> flakes;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in flakes) {
      final p = ((t - f.delay) * f.speed * 1.6);
      if (p <= 0 || p > 1.2) continue;
      final y = p * size.height;
      final x = f.x * size.width + math.sin(p * 8 + f.sway) * 18;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * 6 + f.sway);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: f.size,
          height: f.size * 0.6,
        ),
        Paint()..color = f.color.withValues(alpha: (1.2 - p).clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
