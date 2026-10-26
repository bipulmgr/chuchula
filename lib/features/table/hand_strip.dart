import 'package:flutter/material.dart';

import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/card.dart';
import '../../game/models/game_state.dart';
import '../../game/rules/hand_evaluator.dart';
import '../../widgets/card_widgets.dart';

/// Geometry of the 13-card hand: four groups (3, 3, 3, 4), laid out in one
/// row on wide screens and two rows (groups 1-2, 3-4) on phones so cards
/// stay large enough to read.
class HandLayout {
  HandLayout._(this.cardWidth, this.positions, this.groupRects, this.size);

  factory HandLayout.compute(double maxWidth, {double maxHeight = 300}) {
    const gap = 12.0;
    const labelH = 18.0;
    const overlap = 0.52; // visible fraction of a covered card
    final singleRow = maxWidth >= 620;
    double w;
    if (singleRow) {
      // 4w + 9*overlap*w + 3*gap = maxWidth
      w = (maxWidth - 3 * gap) / (4 + 9 * overlap);
    } else {
      // Widest row holds groups of 3 and 4: 2w + 5*overlap*w + gap.
      w = (maxWidth - gap) / (2 + 5 * overlap);
    }
    final rows = singleRow ? 1 : 2;
    final hLimit = (maxHeight - rows * labelH - (rows - 1) * 8) / rows;
    w = w.clamp(36.0, 96.0);
    if (w / kCardAspect > hLimit) w = hLimit * kCardAspect;
    final cardH = w / kCardAspect;
    final step = w * overlap;

    final positions = <Offset>[];
    final groupRects = <Rect>[];
    double rowWidth(List<int> groups) =>
        groups.fold<double>(0, (t, g) => t + w + (kGroupSizes[g] - 1) * step) +
        (groups.length - 1) * gap;

    final layoutRows = singleRow
        ? [
            [0, 1, 2, 3],
          ]
        : [
            [0, 1],
            [2, 3],
          ];
    final width = layoutRows.map(rowWidth).reduce((a, b) => a > b ? a : b);
    var y = 0.0;
    for (final row in layoutRows) {
      var x = (width - rowWidth(row)) / 2;
      for (final g in row) {
        final gw = w + (kGroupSizes[g] - 1) * step;
        groupRects.add(Rect.fromLTWH(x, y, gw, labelH + cardH));
        for (var i = 0; i < kGroupSizes[g]; i++) {
          positions.add(Offset(x + i * step, y + labelH));
        }
        x += gw + gap;
      }
      y += labelH + cardH + 8;
    }
    return HandLayout._(w, positions, groupRects, Size(width, y - 8));
  }

  final double cardWidth;

  /// Top-left of each of the 13 slots, in hand order.
  final List<Offset> positions;

  /// Bounding box (label + cards) of each group.
  final List<Rect> groupRects;
  final Size size;

  static int groupOfSlot(int slot) {
    var start = 0;
    for (var g = 0; g < kGroupSizes.length; g++) {
      start += kGroupSizes[g];
      if (slot < start) return g;
    }
    return kGroupSizes.length - 1;
  }

  static List<List<PlayingCard>> split(List<PlayingCard> order) {
    final groups = <List<PlayingCard>>[];
    var start = 0;
    for (final n in kGroupSizes) {
      groups.add(order.sublist(start, start + n));
      start += n;
    }
    return groups;
  }
}

enum StripMode { arranging, locked, playing }

/// The local player's thirteen cards. While arranging, cards can be dragged
/// onto each other to swap places, or tapped in pairs (accessible
/// alternative). Every arrangement is a valid 3-3-3-4 split by
/// construction, so cards can never be lost or duplicated.
class HandStrip extends StatefulWidget {
  const HandStrip({
    super.key,
    required this.order,
    required this.mode,
    required this.theme,
    required this.reducedMotion,
    this.onSwap,
    this.onPlayGroup,
    this.playedGroups = 0,
    this.activeGroup,
    this.invalidGroups = const {},
    this.onDragStart,
    this.revealProgress = 1,
  });

  final List<PlayingCard> order;
  final StripMode mode;
  final TableTheme theme;
  final bool reducedMotion;
  final void Function(int from, int to)? onSwap;

  /// Called when the player taps the active group (playing mode).
  final VoidCallback? onPlayGroup;

  /// Number of this player's groups already revealed.
  final int playedGroups;

  /// Group to highlight (the one to play next), if any.
  final int? activeGroup;
  final Set<int> invalidGroups;
  final VoidCallback? onDragStart;

  /// 0..1 progress of the deal reveal animation.
  final double revealProgress;

  @override
  State<HandStrip> createState() => _HandStripState();
}

class _HandStripState extends State<HandStrip> {
  int? _selected;
  int? _hoverTarget;

  @override
  void didUpdateWidget(HandStrip old) {
    super.didUpdateWidget(old);
    if (widget.mode != StripMode.arranging) _selected = null;
  }

  void _tap(int slot) {
    if (widget.mode == StripMode.playing) {
      if (HandLayout.groupOfSlot(slot) == widget.activeGroup) {
        widget.onPlayGroup?.call();
      }
      return;
    }
    if (widget.mode != StripMode.arranging) return;
    setState(() {
      if (_selected == null) {
        _selected = slot;
      } else if (_selected == slot) {
        _selected = null;
      } else {
        widget.onSwap?.call(_selected!, slot);
        _selected = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = HandLayout.compute(
          constraints.maxWidth,
          maxHeight: constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 300,
        );
        final w = layout.cardWidth;
        final groups = HandLayout.split(widget.order);
        final duration = widget.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 260);

        final children = <Widget>[];
        for (var g = 0; g < kGroupCount; g++) {
          final rect = layout.groupRects[g];
          final value = HandEvaluator.evaluate(groups[g]);
          final played = g < widget.playedGroups;
          final active = widget.activeGroup == g;
          final invalid = widget.invalidGroups.contains(g);
          children.add(
            Positioned(
              left: rect.left - 4,
              top: rect.top,
              width: rect.width + 8,
              height: rect.height + 4,
              child: _GroupFrame(
                theme: widget.theme,
                label:
                    '${g + 1} · ${played ? '✓' : l.category(value.category)}',
                active: active,
                invalid: invalid,
                played: played,
              ),
            ),
          );
        }

        for (var slot = 0; slot < widget.order.length; slot++) {
          final card = widget.order[slot];
          final g = HandLayout.groupOfSlot(slot);
          final pos = layout.positions[slot];
          final selected = _selected == slot;
          final played = g < widget.playedGroups;
          final reveal = ((widget.revealProgress * 13) - slot).clamp(0.0, 1.0);
          final lift = selected ? -12.0 : (_hoverTarget == slot ? -6.0 : 0.0);
          Widget face = CardFace(
            card: card,
            width: w,
            dimmed: played,
            highlight: selected
                ? widget.theme.glow
                : (_hoverTarget == slot ? widget.theme.accent : null),
          );
          if (reveal < 1) {
            face = Opacity(
              opacity: reveal,
              child: Transform.translate(
                offset: Offset(0, (1 - reveal) * 30),
                child: face,
              ),
            );
          }
          Widget cardWidget = Semantics(
            button: true,
            selected: selected,
            label: l.cardInGroup(_cardName(card), g + 1),
            onTap: () => _tap(slot),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tap(slot),
              child: face,
            ),
          );
          if (widget.mode == StripMode.arranging) {
            cardWidget = DragTarget<int>(
              onWillAcceptWithDetails: (d) {
                if (d.data == slot) return false;
                setState(() => _hoverTarget = slot);
                return true;
              },
              onLeave: (_) => setState(() => _hoverTarget = null),
              onAcceptWithDetails: (d) {
                setState(() {
                  _hoverTarget = null;
                  _selected = null;
                });
                widget.onSwap?.call(d.data, slot);
              },
              builder: (context, candidate, rejected) => Draggable<int>(
                data: slot,
                onDragStarted: () {
                  setState(() => _selected = null);
                  widget.onDragStart?.call();
                },
                feedback: Transform.scale(
                  scale: 1.12,
                  child: CardFace(
                    card: card,
                    width: w,
                    elevation: 10,
                    highlight: widget.theme.glow,
                  ),
                ),
                childWhenDragging: _GhostCard(width: w, theme: widget.theme),
                child: cardWidget,
              ),
            );
          }
          children.add(
            AnimatedPositioned(
              key: ValueKey(card.id),
              duration: duration,
              curve: Curves.easeOutCubic,
              left: pos.dx,
              top: pos.dy + lift,
              width: w,
              height: w / kCardAspect,
              child: cardWidget,
            ),
          );
        }

        return Center(
          child: SizedBox(
            width: layout.size.width,
            height: layout.size.height + 4,
            child: Stack(clipBehavior: Clip.none, children: children),
          ),
        );
      },
    );
  }

  String _cardName(PlayingCard c) => '${c.rank.label}${c.suit.symbol}';
}

class _GroupFrame extends StatelessWidget {
  const _GroupFrame({
    required this.theme,
    required this.label,
    required this.active,
    required this.invalid,
    required this.played,
  });

  final TableTheme theme;
  final String label;
  final bool active;
  final bool invalid;
  final bool played;

  @override
  Widget build(BuildContext context) {
    final color = invalid
        ? const Color(0xFFFF7A6B)
        : active
        ? theme.glow
        : theme.accent.withValues(alpha: played ? 0.25 : 0.55);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.black.withValues(alpha: active ? 0.22 : 0.12),
        border: Border.all(color: color, width: active ? 2 : 1),
        boxShadow: active
            ? [
                BoxShadow(
                  color: theme.glow.withValues(alpha: 0.45),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.only(left: 6, top: 1),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Mukta',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          height: 1.2,
          color: color,
        ),
      ),
    );
  }
}

class _GhostCard extends StatelessWidget {
  const _GhostCard({required this.width, required this.theme});
  final double width;
  final TableTheme theme;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width / kCardAspect,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(width * 0.1),
      border: Border.all(
        color: theme.accent.withValues(alpha: 0.6),
        width: 1.5,
      ),
      color: Colors.black.withValues(alpha: 0.15),
    ),
  );
}
