import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/card.dart';
import '../../widgets/card_widgets.dart';
import '../../widgets/ornaments.dart';

class HowToPlayScreen extends ConsumerWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = ref.watch(tableThemeProvider);
    const target = 20;
    final sections = <(String, String, List<String>?)>[
      (l.tutGoalTitle, l.tutGoal(target), null),
      (l.tutArrangeTitle, l.tutArrange, null),
      (l.tutPlayTitle, l.tutPlay, null),
      (
        l.tutRankTitle,
        l.tutRank3,
        ['7S 7H 7D', 'QH KH AH', '4C 5D 6S', '2D 9D KD', 'JS JC 3H'],
      ),
      (l.tutRank4Title, l.tutRank4, ['8S 6S 4S 2S', 'AH 9H 5H 3C']),
      (l.tutTieTitle, l.tutTie, null),
      (l.tutScoreTitle, l.tutScore, null),
      (l.tutEndTitle, l.tutEnd(target), null),
    ];
    return Scaffold(
      backgroundColor: theme.feltEdge,
      appBar: AppBar(
        title: Text(l.howToPlay),
        backgroundColor: theme.surface,
        foregroundColor: theme.accentSoft,
      ),
      body: FeltBackground(
        theme: theme,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (title, body, examples) in sections) ...[
              _Section(
                theme: theme,
                title: title,
                body: body,
                examples: examples,
              ),
              const SizedBox(height: 12),
            ],
            Text(
              l.tutInterim,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.theme,
    required this.title,
    required this.body,
    this.examples,
  });

  final TableTheme theme;
  final String title;
  final String body;
  final List<String>? examples;

  @override
  Widget build(BuildContext context) {
    return GoldPanel(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'YatraOne',
              fontSize: 20,
              color: theme.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 15, height: 1.45)),
          if (examples != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 10,
              children: [
                for (final e in examples!)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final c in parseCards(e))
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: CardFace(card: c, width: 30, elevation: 1),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
