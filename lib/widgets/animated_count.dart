import 'package:flutter/material.dart';

/// Counts up (or down) to [value] whenever it changes.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.reducedMotion = false,
    this.prefix = '',
  });

  final int value;
  final TextStyle style;
  final bool reducedMotion;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion) return Text('$prefix$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final shown = v.round();
        final growing = shown != value;
        return AnimatedScale(
          scale: growing ? 1.25 : 1,
          duration: const Duration(milliseconds: 180),
          child: Text('$prefix$shown', style: style),
        );
      },
    );
  }
}
