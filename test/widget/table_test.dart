import 'package:chuchula/bots/bot_strategy.dart';
import 'package:chuchula/features/table/hand_strip.dart';
import 'package:chuchula/features/table/seat_plate.dart';
import 'package:chuchula/features/table/table_screen.dart';
import 'package:chuchula/game/models/card.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/state/authority_session.dart';
import 'package:chuchula/widgets/card_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/test_helpers.dart';
import 'test_app.dart';

// Seat 0's dealt hand. No 10, so it is not an all-ranks instant win.
const _hand = '2C 2D 5H 9S KC 3D 7H JS AC 4D 8H QS 6C';

AuthorityGameSession _session() {
  final engine = fixedEngine([
    deckFor([_hand]),
    deckFor([_hand]),
  ]);
  return AuthorityGameSession(
    engine: engine,
    initialState: start(engine),
    localSeat: 0,
    bots: {for (var s = 1; s < 4; s++) s: const MediumBot()},
    timing: const BotTiming.instant(),
    botRunner: inlineBotRunner,
  );
}

List<PlayingCard> _order(WidgetTester tester) =>
    tester.widget<HandStrip>(find.byType(HandStrip)).order;

Finder _cardAt(WidgetTester tester, int slot) {
  final card = _order(tester)[slot];
  return find.descendant(
    of: find.byType(HandStrip),
    matching: find.byWidgetPredicate((w) => w is CardFace && w.card == card),
  );
}

Future<void> _settle(WidgetTester tester) async {
  // Bot moves and summary timers are short; step real time forward.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('shows my 13 cards in 3-3-3-4 groups and four seats', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    final strip = find.byType(HandStrip);
    expect(
      find.descendant(of: strip, matching: find.byType(CardFace)),
      findsNWidgets(13),
    );
    expect(_order(tester).toSet(), parseCards(_hand).toSet());
    expect(find.byType(SeatPlate), findsNWidgets(4));
    expect(find.byKey(const Key('readyButton')), findsOneWidget);
    await session.dispose();
  });

  testWidgets('tapping two cards swaps them', (tester) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    final before = _order(tester);
    await tester.tap(_cardAt(tester, 0));
    await tester.pump();
    await tester.tap(_cardAt(tester, 12));
    await _settle(tester);
    final after = _order(tester);
    expect(after[0], before[12]);
    expect(after[12], before[0]);
    expect(after.toSet(), before.toSet());
    await session.dispose();
  });

  testWidgets('dragging a card onto another swaps them', (tester) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    final before = _order(tester);
    final from = tester.getCenter(_cardAt(tester, 1));
    final to = tester.getCenter(_cardAt(tester, 10));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await _settle(tester);
    final after = _order(tester);
    expect(after[1], before[10]);
    expect(after[10], before[1]);
    expect(after.length, 13);
    await session.dispose();
  });

  testWidgets('ready, play every group, and see the round scored', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('readyButton')));
    await _settle(tester);
    expect(session.view.value!.ready[0], isTrue);
    expect(session.view.value!.phase, GamePhase.playing);

    // Play whenever it is my turn until the round is over.
    for (var i = 0; i < 4; i++) {
      final v = session.view.value!;
      if (v.phase != GamePhase.playing) break;
      expect(v.isMyTurn, isTrue, reason: 'bots wait for me');
      expect(find.byKey(const Key('playGroupButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('playGroupButton')));
      await _settle(tester);
    }
    final v = session.view.value!;
    expect(v.phase, isNot(GamePhase.playing));
    expect(v.scores.reduce((a, b) => a + b), greaterThan(0));

    // Each seat plate announces its score.
    for (var seat = 0; seat < 4; seat++) {
      final plate = tester.widget<SeatPlate>(
        find.byWidgetPredicate((w) => w is SeatPlate && w.seat == seat).first,
      );
      expect(plate.score, v.scores[seat]);
    }
    if (v.phase == GamePhase.roundOver) {
      expect(find.byKey(const Key('nextRoundButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('nextRoundButton')));
      await _settle(tester);
      expect(session.view.value!.round, 2);
      expect(session.view.value!.phase, GamePhase.arranging);
    }
    await session.dispose();
  });

  testWidgets('a rejected move is shown to the player', (tester) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    // Not my turn yet: the engine rejects playing before arranging.
    await session.playGroup();
    await tester.pump();
    expect(find.byType(TableScreen), findsOneWidget);
    expect(session.view.value!.phase, GamePhase.arranging);
    await _settle(tester);
    await session.dispose();
  });
}
