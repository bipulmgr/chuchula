import 'package:flutter/material.dart';

import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/card.dart';
import '../../game/models/game_state.dart';
import '../../game/models/player_view.dart';
import '../../game/rules/hand_evaluator.dart';
import '../../widgets/card_widgets.dart';

/// Relative table position of [seat] as seen from [mySeat]:
/// 0 bottom, 1 right, 2 top, 3 left.
int relativePosition(int seat, int mySeat) => (seat - mySeat + 4) % 4;

const _slotAlignments = [
  Alignment(0, 0.82),
  Alignment(0.92, 0),
  Alignment(0, -0.82),
  Alignment(-0.92, 0),
];

const _entryOffsets = [
  Offset(0, 1.6),
  Offset(1.6, 0),
  Offset(0, -1.6),
  Offset(-1.6, 0),
];

/// Which group the center should show: the group in play, or the group just
/// finished while nobody has led the next one yet (so its winner stays
/// visible).
int displayGroup(PlayerView v) {
  if (v.roundPlays.isEmpty) return 0;
  if (v.phase == GamePhase.roundOver || v.phase == GamePhase.matchOver) {
    return v.roundPlays.length - 1;
  }
  final g = v.groupIndex.clamp(0, v.roundPlays.length - 1);
  final current = v.roundPlays[g];
  if (g > 0 && current.every((p) => p == null)) return g - 1;
  return g;
}

/// The shared playing area: each seat's revealed group for the group in
/// play, with the winner highlighted once all four are down.
class CenterArea extends StatelessWidget {
  const CenterArea({
    super.key,
    required this.view,
    required this.theme,
    required this.reducedMotion,
  });

  final PlayerView view;
  final TableTheme theme;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (view.roundPlays.isEmpty) {
      return Center(
        child: _ProgressPips(view: view, theme: theme),
      );
    }
    final g = displayGroup(view);
    final plays = view.roundPlays[g];
    final complete = g < view.groupWinners.length;
    final winner = complete ? view.groupWinners[g] : null;

    return LayoutBuilder(
      builder: (context, c) {
        final cardW = (c.maxWidth / 9.5).clamp(26.0, 46.0);
        return Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    g == 3 ? l.groupOfFour : l.groupLabel(g + 1),
                    style: TextStyle(
                      fontFamily: 'YatraOne',
                      fontSize: 18,
                      color: theme.accentSoft.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _ProgressPips(view: view, theme: theme),
                ],
              ),
            ),
            for (var seat = 0; seat < kSeatCount; seat++)
              if (plays[seat] != null)
                Align(
                  alignment:
                      _slotAlignments[relativePosition(seat, view.mySeat)],
                  child: _PlayedGroup(
                    key: ValueKey('${view.round}-$g-$seat'),
                    cards: plays[seat]!,
                    cardWidth: cardW,
                    theme: theme,
                    winner: winner == seat,
                    from: _entryOffsets[relativePosition(seat, view.mySeat)],
                    reducedMotion: reducedMotion,
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _PlayedGroup extends StatelessWidget {
  const _PlayedGroup({
    super.key,
    required this.cards,
    required this.cardWidth,
    required this.theme,
    required this.winner,
    required this.from,
    required this.reducedMotion,
  });

  final List<PlayingCard> cards;
  final double cardWidth;
  final TableTheme theme;
  final bool winner;
  final Offset from;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = HandEvaluator.evaluate(cards);
    final step = cardWidth * 0.62;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: cardWidth + step * (cards.length - 1),
          height: cardWidth / kCardAspect,
          child: Stack(
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  left: i * step,
                  child: CardFace(
                    card: cards[i],
                    width: cardWidth,
                    highlight: winner ? theme.glow : null,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: winner ? theme.glow : Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            l.category(value.category),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: winner ? const Color(0xFF2B1A05) : theme.onSurface,
            ),
          ),
        ),
      ],
    );
    if (reducedMotion) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => FractionalTranslation(
        translation: from * (1 - t),
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
      child: AnimatedScale(
        scale: winner ? 1.08 : 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutBack,
        child: body,
      ),
    );
  }
}

/// Four pips showing which groups are done and who won them.
class _ProgressPips extends StatelessWidget {
  const _ProgressPips({required this.view, required this.theme});

  final PlayerView view;
  final TableTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var g = 0; g < kGroupCount; g++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _pip(g),
          ),
      ],
    );
  }

  Widget _pip(int g) {
    final won = g < view.groupWinners.length;
    final active =
        view.phase == GamePhase.playing && g == view.groupIndex && !won;
    final winnerSeat = won ? view.groupWinners[g] : null;
    final color = winnerSeat == null
        ? null
        : avatarColors[view.seats[winnerSeat].avatar % avatarColors.length];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? Colors.black.withValues(alpha: 0.3),
        border: Border.all(
          color: active ? theme.glow : theme.accent.withValues(alpha: 0.6),
          width: active ? 2 : 1,
        ),
      ),
      child: Text(
        '${g + 1}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color != null ? const Color(0xFF2B1A05) : theme.onSurface,
        ),
      ),
    );
  }
}
