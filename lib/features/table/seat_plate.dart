import 'package:flutter/material.dart';

import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/game_state.dart';
import '../../game/state/game_session.dart';
import '../../widgets/animated_count.dart';

/// A player's seat: avatar, name, score, status and a turn indicator.
class SeatPlate extends StatefulWidget {
  const SeatPlate({
    super.key,
    required this.seat,
    required this.info,
    required this.score,
    required this.theme,
    required this.connection,
    required this.isTurn,
    required this.isReady,
    required this.isThinking,
    required this.isDealer,
    required this.phase,
    required this.reducedMotion,
    this.compact = false,
  });

  final int seat;
  final SeatInfo info;
  final int score;
  final TableTheme theme;
  final SeatConnection connection;
  final bool isTurn;
  final bool isReady;
  final bool isThinking;
  final bool isDealer;
  final GamePhase phase;
  final bool reducedMotion;
  final bool compact;

  @override
  State<SeatPlate> createState() => _SeatPlateState();
}

class _SeatPlateState extends State<SeatPlate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SeatPlate old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.isTurn && !widget.reducedMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = widget.isTurn ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = widget.theme;
    final avatar = widget.info.avatar % avatarColors.length;
    final size = widget.compact ? 40.0 : 48.0;

    String? status;
    Widget? statusIcon;
    if (widget.connection == SeatConnection.reconnecting) {
      status = l.statusReconnecting;
      statusIcon = const Icon(
        Icons.wifi_off,
        size: 12,
        color: Color(0xFFFFB0A0),
      );
    } else if (widget.connection == SeatConnection.disconnected) {
      status = l.statusDisconnected;
      statusIcon = const Icon(
        Icons.wifi_off,
        size: 12,
        color: Color(0xFFFFB0A0),
      );
    } else if (widget.phase == GamePhase.arranging) {
      if (widget.isReady) {
        status = l.readyCheck;
        statusIcon = Icon(Icons.check_circle, size: 12, color: t.glow);
      } else if (widget.isThinking) {
        status = l.thinking;
        statusIcon = SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: t.accentSoft,
          ),
        );
      }
    }
    status ??= switch (widget.connection) {
      SeatConnection.bot => l.statusBot,
      SeatConnection.local => l.statusYou,
      _ => l.statusConnected,
    };

    return Semantics(
      label: l.seatScore(widget.info.name, widget.score),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final glow = widget.isTurn ? 0.35 + 0.45 * _pulse.value : 0.0;
          return Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(size),
              border: Border.all(
                color: widget.isTurn
                    ? t.glow
                    : t.accent.withValues(alpha: 0.45),
                width: widget.isTurn ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: t.glow.withValues(alpha: glow),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color.lerp(avatarColors[avatar], Colors.white, 0.25)!,
                        avatarColors[avatar],
                      ],
                    ),
                    border: Border.all(color: t.accentSoft, width: 1.5),
                  ),
                  child: Icon(
                    avatarIcons[avatar],
                    size: size * 0.55,
                    color: const Color(0xFF2B1A05),
                  ),
                ),
                if (widget.isDealer)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.surface, width: 1.5),
                      ),
                      child: const Text(
                        'D',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: Color(0xFF2B1A05),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.compact ? 72 : 96,
                  ),
                  child: Text(
                    widget.info.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Mukta',
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      height: 1.1,
                      color: t.onSurface,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedCount(
                      value: widget.score,
                      reducedMotion: widget.reducedMotion,
                      style: TextStyle(
                        fontFamily: 'Mukta',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.1,
                        color: t.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (statusIcon != null) ...[
                      statusIcon,
                      const SizedBox(width: 3),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 74),
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          color: t.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
