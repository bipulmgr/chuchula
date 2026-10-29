import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/table_themes.dart';

/// The felt table background with a subtle vignette and ornamental rim.
class FeltBackground extends StatelessWidget {
  const FeltBackground({super.key, required this.theme, required this.child});

  final TableTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(gradient: theme.feltGradient),
      child: CustomPaint(painter: _FeltTexturePainter(theme), child: child),
    );
  }
}

class _FeltTexturePainter extends CustomPainter {
  _FeltTexturePainter(this.theme);
  final TableTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    // Faint woven texture.
    final rnd = math.Random(7);
    final p = Paint()..color = Colors.white.withValues(alpha: 0.018);
    for (var i = 0; i < 900; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        rnd.nextDouble() * 1.2,
        p,
      );
    }
    // Ornamental inner border (corner motifs + thin gold line).
    final inset = 10.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - inset * 2,
        size.height - inset * 2,
      ),
      const Radius.circular(22),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.accent.withValues(alpha: 0.28),
    );
    for (final corner in [
      Offset(inset + 16, inset + 16),
      Offset(size.width - inset - 16, inset + 16),
      Offset(inset + 16, size.height - inset - 16),
      Offset(size.width - inset - 16, size.height - inset - 16),
    ]) {
      _drawStar(canvas, corner, 6, theme.accent.withValues(alpha: 0.35));
    }
  }

  void _drawStar(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      final rr = i.isEven ? r : r * 0.45;
      final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FeltTexturePainter old) => old.theme.id != theme.id;
}

/// A panel with a gold double border used for dialogs and plates.
class GoldPanel extends StatelessWidget {
  const GoldPanel({
    super.key,
    required this.theme,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
  });

  final TableTheme theme;
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 3),
        gradient: LinearGradient(
          colors: [theme.accentSoft, theme.accent, theme.accentSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // A Material (not a decorated box) so list tiles and ink splashes
      // inside the panel paint on it.
      child: Material(
        color: theme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: theme.accent.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: padding,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: theme.onSurface),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Chuchula word mark: Devanagari title above the Latin name.
class ChuchulaLogo extends StatelessWidget {
  const ChuchulaLogo({super.key, required this.theme, this.size = 64});

  final TableTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gold = LinearGradient(
      colors: [theme.accentSoft, theme.accent, const Color(0xFFB9852B)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    return Semantics(
      header: true,
      label: 'Chuchula',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (r) => gold.createShader(r),
              child: Text(
                'चुचुला',
                style: TextStyle(
                  fontFamily: 'YatraOne',
                  fontSize: size,
                  height: 1.1,
                  color: Colors.white,
                  shadows: const [
                    Shadow(blurRadius: 12, color: Colors.black54),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _rule(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'CHUCHULA',
                    style: TextStyle(
                      fontFamily: 'Mukta',
                      fontWeight: FontWeight.w800,
                      letterSpacing: size * 0.12,
                      fontSize: size * 0.28,
                      color: theme.accentSoft,
                    ),
                  ),
                ),
                _rule(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rule() => Container(
    width: size * 0.6,
    height: 1.5,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [theme.accent.withValues(alpha: 0), theme.accent],
      ),
    ),
  );
}

/// A tactile gold button with a press-down animation.
class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.theme,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = true,
    this.expand = true,
    this.subtitle,
    this.dense = false,
  });

  final TableTheme theme;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool expand;

  /// Tighter padding and type, for narrow toolbars.
  final bool dense;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final enabled = widget.onPressed != null;
    final fg = widget.primary ? const Color(0xFF2B1A05) : t.onSurface;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, color: fg, size: 22),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Mukta',
                  fontWeight: FontWeight.w800,
                  fontSize: widget.dense ? 15 : 17,
                  color: fg,
                  height: 1.1,
                ),
              ),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: fg.withValues(alpha: 0.75),
                    height: 1.1,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.96 : 1,
            duration: const Duration(milliseconds: 90),
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.45,
              duration: const Duration(milliseconds: 200),
              child: Container(
                constraints: const BoxConstraints(minHeight: 50),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.dense ? 6 : 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: widget.primary
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            t.accentSoft,
                            t.accent,
                            const Color(0xFFB27F25),
                          ],
                        )
                      : null,
                  color: widget.primary
                      ? null
                      : t.surface.withValues(alpha: 0.85),
                  border: Border.all(
                    color: widget.primary
                        ? const Color(0xFFFFF1C4)
                        : t.accent.withValues(alpha: 0.7),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: _down ? 0.2 : 0.4),
                      blurRadius: _down ? 4 : 10,
                      offset: Offset(0, _down ? 1 : 4),
                    ),
                  ],
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
