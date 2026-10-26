import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/card.dart';
import '../../game/models/game_state.dart';
import '../../game/models/player_view.dart';
import '../../game/rules/hand_evaluator.dart';
import '../../widgets/animated_count.dart';
import '../../widgets/card_widgets.dart';
import '../../widgets/ornaments.dart';

/// Round results: everyone's revealed groups, who won each, bonuses and
/// points.
class RoundSummaryPanel extends StatelessWidget {
  const RoundSummaryPanel({
    super.key,
    required this.view,
    required this.theme,
    required this.onNext,
    required this.reducedMotion,
  });

  final PlayerView view;
  final TableTheme theme;

  /// Null when only the host may deal the next round.
  final VoidCallback? onNext;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rr = view.lastRound!;
    final order = List.generate(kSeatCount, (i) => i)
      ..sort((a, b) => view.scores[b].compareTo(view.scores[a]));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: GoldPanel(
            theme: theme,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.roundSummary(rr.round),
                  style: TextStyle(
                    fontFamily: 'YatraOne',
                    fontSize: 24,
                    color: theme.accent,
                  ),
                ),
                if (rr.sweepSeat != null)
                  _Banner(
                    text: '${view.seats[rr.sweepSeat!].name}: ${l.sweep}',
                    theme: theme,
                  ),
                for (var seat = 0; seat < kSeatCount; seat++)
                  for (final b in rr.bonuses[seat])
                    _Banner(
                      text: l.bonusBy(
                        view.seats[seat].name,
                        l.bonus(b.type),
                        b.points,
                      ),
                      theme: theme,
                    ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final seat in order)
                          _SeatRow(
                            seat: seat,
                            view: view,
                            theme: theme,
                            reducedMotion: reducedMotion,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (onNext != null)
                  GoldButton(
                    key: const Key('nextRoundButton'),
                    theme: theme,
                    label: l.nextRound,
                    icon: Icons.style,
                    onPressed: onNext,
                  )
                else
                  Text(
                    l.waitingForHost,
                    style: TextStyle(color: theme.onSurface),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.theme});
  final String text;
  final TableTheme theme;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [theme.accent, theme.glow]),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF2B1A05)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF2B1A05),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({
    required this.seat,
    required this.view,
    required this.theme,
    required this.reducedMotion,
  });

  final int seat;
  final PlayerView view;
  final TableTheme theme;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rr = view.lastRound!;
    final arrangement = rr.arrangements[seat];
    final points = rr.points[seat];
    final isMe = seat == view.mySeat;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? theme.accent.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  view.seats[seat].name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: theme.onSurface,
                  ),
                ),
              ),
              Text(
                points > 0 ? '+$points' : '0',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: points > 0 ? theme.glow : theme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              AnimatedCount(
                value: view.scores[seat],
                reducedMotion: reducedMotion,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: theme.accent,
                ),
              ),
            ],
          ),
          if (arrangement != null) ...[
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, c) {
                // 13 cards plus gaps across the row.
                final w = math.min(30.0, (c.maxWidth - 24) / 9.2);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var g = 0; g < kGroupCount; g++)
                      _MiniGroup(
                        cards: arrangement.groups[g],
                        width: w,
                        won: rr.groupWinners[g] == seat,
                        label: l.handName(
                          HandEvaluator.evaluate(arrangement.groups[g]),
                        ),
                        theme: theme,
                      ),
                  ],
                );
              },
            ),
          ] else if (rr.shownSeat == seat && rr.instantWinHand != null) ...[
            // The special hand this player showed.
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, c) => _MiniGroup(
                cards: rr.instantWinHand!,
                width: math.min(34.0, c.maxWidth / 7.8),
                won: true,
                label: rr.bonuses[seat].map((b) => l.bonus(b.type)).join(' + '),
                theme: theme,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniGroup extends StatelessWidget {
  const _MiniGroup({
    required this.cards,
    required this.width,
    required this.won,
    required this.label,
    required this.theme,
  });

  final List<PlayingCard> cards;
  final double width;
  final bool won;
  final String label;
  final TableTheme theme;

  @override
  Widget build(BuildContext context) {
    final step = width * 0.55;
    final groupWidth = width + step * (cards.length - 1);
    return Column(
      children: [
        SizedBox(
          width: groupWidth,
          height: width / kCardAspect,
          child: Stack(
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  left: i * step,
                  child: CardFace(
                    card: cards[i],
                    width: width,
                    elevation: 1,
                    highlight: won ? theme.glow : null,
                  ),
                ),
            ],
          ),
        ),
        // Category names are wider than a small group; shrink to fit.
        SizedBox(
          width: groupWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              won ? '★ $label' : label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                color: won
                    ? theme.glow
                    : theme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
