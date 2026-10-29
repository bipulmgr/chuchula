import 'package:flutter/material.dart';

import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/game_state.dart';
import '../../game/models/player_view.dart';

/// Opens the points table: every round's points per player and the
/// running totals.
Future<void> showPointsTable(
  BuildContext context,
  PlayerView view,
  TableTheme theme,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: theme.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
  ),
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    child: PointsTable(view: view, theme: theme),
  ),
);

class PointsTable extends StatelessWidget {
  const PointsTable({super.key, required this.view, required this.theme});

  final PlayerView view;
  final TableTheme theme;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rounds = view.history;
    final head = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 12.5,
      color: theme.accentSoft,
    );
    final body = TextStyle(fontSize: 14, color: theme.onSurface);
    final total = TextStyle(
      fontFamily: 'Mukta',
      fontWeight: FontWeight.w800,
      fontSize: 16,
      color: theme.accent,
    );

    Widget cell(String text, TextStyle style, {bool first = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: first ? TextAlign.start : TextAlign.center,
        style: style,
      ),
    );

    final line = BorderSide(color: theme.accent.withValues(alpha: 0.25));
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l.pointsTable,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'YatraOne',
                fontSize: 22,
                color: theme.accent,
              ),
            ),
            Text(
              l.targetScore(view.targetScore),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Table(
                  key: const Key('pointsTable'),
                  columnWidths: const {0: FlexColumnWidth(1.1)},
                  border: TableBorder(horizontalInside: line),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(border: Border(bottom: line)),
                      children: [
                        cell(l.roundColumn, head, first: true),
                        for (var s = 0; s < kSeatCount; s++)
                          cell(
                            s == view.mySeat
                                ? l.defaultPlayerName
                                : view.seats[s].name,
                            head,
                          ),
                      ],
                    ),
                    for (final r in rounds)
                      TableRow(
                        children: [
                          cell(l.roundLabel(r.round), body, first: true),
                          for (var s = 0; s < kSeatCount; s++)
                            cell(
                              r.points[s] == 0 ? '–' : '+${r.points[s]}',
                              body.copyWith(
                                fontWeight: r.points[s] > 0
                                    ? FontWeight.w800
                                    : FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                    TableRow(
                      decoration: BoxDecoration(
                        color: theme.accent.withValues(alpha: 0.12),
                      ),
                      children: [
                        cell(l.totalColumn, head, first: true),
                        for (var s = 0; s < kSeatCount; s++)
                          cell('${view.scores[s]}', total),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (rounds.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  l.noRoundsYet,
                  textAlign: TextAlign.center,
                  style: body.copyWith(
                    color: theme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
