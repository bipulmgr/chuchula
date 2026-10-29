import 'package:flutter/material.dart';

import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/card.dart';
import '../../game/rules/hand_evaluator.dart';
import '../../widgets/card_widgets.dart';

/// Geometry of the 13-card hand: four groups (one of 4 cards, three of 3,
/// in any position), laid out in one row on wide screens and two rows
/// (groups 1-2, 3-4) on phones so cards stay large enough to read.
class HandLayout {
  HandLayout._(
    this.cardWidth,
    this.positions,
    this.groupRects,
    this.slotGroups,
    this.size,
  );

  static const labelHeight = 18.0;

  factory HandLayout.compute(
    double maxWidth,
    List<int> sizes, {
    double maxHeight = 300,
  }) {
    const gap = 12.0;
    const labelH = labelHeight;
    const overlap = 0.52; // visible fraction of a covered card
    // Group frames reach 4px past their cards on each side.
    const margin = 4.0;
    final avail = maxWidth - 2 * margin;
    final singleRow = maxWidth >= 600;
    double w;
    if (singleRow) {
      // 4w + 9*overlap*w + 3*gap = avail
      w = (avail - 3 * gap) / (4 + 9 * overlap);
    } else {
      // Widest row holds groups of 3 and 4: 2w + 5*overlap*w + gap. On
      // phones cards are kept a little smaller than the width allows, so
      // the table keeps room.
      w = (avail - gap) / (2 + 5 * overlap);
      w = w.clamp(0.0, maxWidth * 0.165);
    }
    final rows = singleRow ? 1 : 2;
    final hLimit = (maxHeight - rows * labelH - (rows - 1) * 8) / rows;
    w = w.clamp(30.0, 92.0);
    if (w / kCardAspect > hLimit) w = hLimit * kCardAspect;
    final cardH = w / kCardAspect;
    final step = w * overlap;

    final positions = <Offset>[];
    final groupRects = <Rect>[];
    final slotGroups = <int>[];
    double rowWidth(List<int> groups) =>
        groups.fold<double>(0, (t, g) => t + w + (sizes[g] - 1) * step) +
        (groups.length - 1) * gap;

    final layoutRows = singleRow
        ? [
            [0, 1, 2, 3],
          ]
        : [
            [0, 1],
            [2, 3],
          ];
    final width =
        layoutRows.map(rowWidth).reduce((a, b) => a > b ? a : b) + 2 * margin;
    var y = 0.0;
    for (final row in layoutRows) {
      var x = (width - rowWidth(row)) / 2;
      for (final g in row) {
        final gw = w + (sizes[g] - 1) * step;
        groupRects.add(Rect.fromLTWH(x, y, gw, labelH + cardH));
        for (var i = 0; i < sizes[g]; i++) {
          positions.add(Offset(x + i * step, y + labelH));
          slotGroups.add(g);
        }
        x += gw + gap;
      }
      y += labelH + cardH + 8;
    }
    return HandLayout._(
      w,
      positions,
      groupRects,
      slotGroups,
      Size(width, y - 8),
    );
  }

  final double cardWidth;

  /// Top-left of each of the 13 slots, in hand order.
  final List<Offset> positions;

  /// Bounding box (label + cards) of each group.
  final List<Rect> groupRects;

  /// Group index of each slot.
  final List<int> slotGroups;
  final Size size;
}

enum StripMode { arranging, locked, playing }

/// Data carried while a whole group is dragged by its label.
class _GroupDrag {
  const _GroupDrag(this.group);
  final int group;
}

/// The local player's thirteen cards. While arranging, cards can be dragged
/// onto each other to swap places, or tapped in pairs (accessible
/// alternative); whole groups swap the same way by their labels. Every
/// arrangement is a valid 3-3-3-4 split by construction, so cards can never
/// be lost or duplicated.
class HandStrip extends StatefulWidget {
  const HandStrip({
    super.key,
    required this.groups,
    required this.mode,
    required this.theme,
    required this.reducedMotion,
    this.onSwap,
    this.onSwapGroups,
    this.onPlayGroup,
    this.playedGroups = 0,
    this.activeGroup,
    this.invalidGroups = const {},
    this.onDragStart,
    this.revealProgress = 1,
  });

  final List<List<PlayingCard>> groups;
  final StripMode mode;
  final TableTheme theme;
  final bool reducedMotion;

  /// Swaps two cards, by slot in the flattened hand.
  final void Function(int from, int to)? onSwap;

  /// Swaps two whole groups.
  final void Function(int from, int to)? onSwapGroups;

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
  int? _selectedGroup;
  int? _draggingGroup;
  int? _hoverGroup;

  @override
  void didUpdateWidget(HandStrip old) {
    super.didUpdateWidget(old);
    if (widget.mode != StripMode.arranging) {
      _selected = null;
      _selectedGroup = null;
      _draggingGroup = null;
      _hoverGroup = null;
    }
  }

  void _tap(int slot, int group) {
    if (widget.mode == StripMode.playing) {
      if (group == widget.activeGroup) widget.onPlayGroup?.call();
      return;
    }
    if (widget.mode != StripMode.arranging) return;
    setState(() {
      _selectedGroup = null;
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

  void _tapGroup(int g) {
    if (widget.mode != StripMode.arranging) return;
    setState(() {
      _selected = null;
      if (_selectedGroup == null) {
        _selectedGroup = g;
      } else if (_selectedGroup == g) {
        _selectedGroup = null;
      } else {
        widget.onSwapGroups?.call(_selectedGroup!, g);
        _selectedGroup = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final groups = widget.groups;
        final order = [for (final g in groups) ...g];
        final layout = HandLayout.compute(
          constraints.maxWidth,
          [for (final g in groups) g.length],
          maxHeight: constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 300,
        );
        final w = layout.cardWidth;
        final duration = widget.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 260);
        final arranging = widget.mode == StripMode.arranging;

        final children = <Widget>[];
        for (var g = 0; g < groups.length; g++) {
          final rect = layout.groupRects[g];
          final value = HandEvaluator.evaluate(groups[g]);
          final played = g < widget.playedGroups;
          final active =
              widget.activeGroup == g ||
              _selectedGroup == g ||
              _hoverGroup == g;
          final invalid = widget.invalidGroups.contains(g);
          final name = l.handName(value);
          final label = '${g + 1} · ${played ? '✓' : name}';
          children.add(
            Positioned(
              left: rect.left - 4,
              top: rect.top,
              width: rect.width + 8,
              height: rect.height + 4,
              child: _GroupFrame(
                theme: widget.theme,
                label: label,
                handle: arranging,
                active: active,
                invalid: invalid,
                played: played,
              ),
            ),
          );
          if (arranging) {
            // The label strip is the handle for moving the whole group.
            final chip = _GroupChip(theme: widget.theme, label: label);
            children.add(
              Positioned(
                left: rect.left - 4,
                top: rect.top,
                width: rect.width + 8,
                height: HandLayout.labelHeight,
                child: Semantics(
                  button: true,
                  selected: _selectedGroup == g,
                  label: l.swapGroupLabel(g + 1, name),
                  onTap: () => _tapGroup(g),
                  child: Draggable<_GroupDrag>(
                    key: Key('groupHandle$g'),
                    data: _GroupDrag(g),
                    onDragStarted: () {
                      setState(() {
                        _selected = null;
                        _selectedGroup = null;
                        _draggingGroup = g;
                      });
                      widget.onDragStart?.call();
                    },
                    onDragEnd: (_) => setState(() {
                      _draggingGroup = null;
                      _hoverGroup = null;
                    }),
                    feedback: chip,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _tapGroup(g),
                    ),
                  ),
                ),
              ),
            );
          }
        }

        for (var slot = 0; slot < order.length; slot++) {
          final card = order[slot];
          final g = layout.slotGroups[slot];
          final pos = layout.positions[slot];
          final selected = _selected == slot;
          final played = g < widget.playedGroups;
          final reveal = ((widget.revealProgress * 13) - slot).clamp(0.0, 1.0);
          final lift = selected ? -12.0 : (_hoverTarget == slot ? -6.0 : 0.0);
          Widget face = CardFace(
            card: card,
            width: w,
            dimmed: played || (_draggingGroup == g),
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
            onTap: () => _tap(slot, g),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tap(slot, g),
              child: face,
            ),
          );
          if (arranging) {
            // Captured as a final: the builder closure below must not see
            // the reassigned variable (that recursed forever).
            final tappable = cardWidget;
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
                  setState(() {
                    _selected = null;
                    _selectedGroup = null;
                  });
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
                child: tappable,
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

        // While a group is being dragged, every group's whole area becomes
        // a drop target, above the cards.
        if (_draggingGroup != null) {
          for (var g = 0; g < groups.length; g++) {
            final rect = layout.groupRects[g];
            children.add(
              Positioned(
                left: rect.left - 4,
                top: rect.top,
                width: rect.width + 8,
                height: rect.height + 4,
                child: DragTarget<_GroupDrag>(
                  onWillAcceptWithDetails: (d) {
                    if (d.data.group == g) return false;
                    setState(() => _hoverGroup = g);
                    return true;
                  },
                  onLeave: (_) => setState(() => _hoverGroup = null),
                  onAcceptWithDetails: (d) {
                    setState(() {
                      _hoverGroup = null;
                      _draggingGroup = null;
                    });
                    widget.onSwapGroups?.call(d.data.group, g);
                  },
                  builder: (context, candidate, rejected) =>
                      const SizedBox.expand(),
                ),
              ),
            );
          }
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

/// What follows the finger while a group is dragged.
class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.theme, required this.label});
  final TableTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.glow, width: 1.5),
        boxShadow: [
          BoxShadow(color: theme.glow.withValues(alpha: 0.5), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz, size: 16, color: theme.glow),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Mukta',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: theme.accentSoft,
            ),
          ),
        ],
      ),
    ),
  );
}

class _GroupFrame extends StatelessWidget {
  const _GroupFrame({
    required this.theme,
    required this.label,
    required this.active,
    required this.invalid,
    required this.played,
    this.handle = false,
  });

  final TableTheme theme;
  final String label;

  /// Shows a drag-handle icon: the label moves the whole group.
  final bool handle;
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
      child: Row(
        children: [
          if (handle) ...[
            Icon(Icons.drag_indicator, size: 13, color: color),
            const SizedBox(width: 1),
          ],
          Expanded(
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
          ),
        ],
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
