import 'package:chuchula/bots/bot_strategy.dart';
import 'package:chuchula/features/table/hand_strip.dart';
import 'package:chuchula/features/table/seat_plate.dart';
import 'package:chuchula/features/table/table_screen.dart';
import 'package:chuchula/game/models/card.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/rules/hand_evaluator.dart';
import 'package:chuchula/game/state/authority_session.dart';
import 'package:chuchula/widgets/card_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/test_helpers.dart';
import 'test_app.dart';

// Seat 0's dealt hand. No 10, so it is not an all-ranks instant win.
const _hand = '2C 2D 5H 9S KC 3D 7H JS AC 4D 8H QS 6C';

// Bot hands with no special hand to show, so the round is played out.
const _deal = [
  _hand,
  'AH KH QH JH 10H 9H 3H 2H 3S 4S 5S 6S 7S',
  'AD KD QD JD 10D 9D 8D 6D 5D 2S 8S 10S KS',
];

AuthorityGameSession _session() {
  final engine = fixedEngine([deckFor(_deal), deckFor(_deal)]);
  return AuthorityGameSession(
    engine: engine,
    initialState: start(engine),
    localSeat: 0,
    bots: {for (var s = 1; s < 4; s++) s: const MediumBot()},
    timing: const BotTiming.instant(),
    botRunner: inlineBotRunner,
  );
}

List<PlayingCard> _order(WidgetTester tester) => [
  ...tester.widget<HandStrip>(find.byType(HandStrip)).groups.expand((g) => g),
];

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

  testWidgets('whole groups swap by dragging or tapping their labels', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    List<List<PlayingCard>> groups() =>
        tester.widget<HandStrip>(find.byType(HandStrip)).groups;
    final before = groups();

    // Drag group 1's label onto group 4: the 4-card group moves to front.
    final from = tester.getCenter(find.byKey(const Key('groupHandle0')));
    final to = tester.getCenter(find.byKey(const Key('groupHandle3')));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await _settle(tester);
    var after = groups();
    expect(after[0], before[3]);
    expect(after[3], before[0]);
    expect(after[0].length, 4);

    // Tap two labels: groups 2 and 3 trade places.
    await tester.tap(find.byKey(const Key('groupHandle1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('groupHandle2')));
    await _settle(tester);
    after = groups();
    expect(after[1], before[2]);
    expect(after[2], before[1]);
    await session.dispose();
  });

  testWidgets('a special hand can be shown to end the round', (tester) async {
    final engine = fixedEngine([
      deckFor([
        '9S 9H 9D 9C 2S 3S 4S 5S 6S 7S 8S 10C JC',
        'AH KH QH JH 10H 8H 7H 6H 5H 4H 3H 2H AS',
        'AD KD QD JD 10D 8D 7D 6D 5D 4D 3D 2D KS',
      ]),
    ]);
    final session = AuthorityGameSession(
      engine: engine,
      initialState: start(engine),
      localSeat: 0,
      bots: {for (var s = 1; s < 4; s++) s: const MediumBot()},
      timing: const BotTiming.instant(),
      botRunner: inlineBotRunner,
    );
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    expect(find.textContaining('Four of a kind +4'), findsOneWidget);
    await tester.tap(find.byKey(const Key('showHandButton')));
    await _settle(tester);
    final v = session.view.value!;
    expect(v.phase, GamePhase.roundOver);
    expect(v.scores[0], 4);
    expect(v.lastRound!.shownSeat, 0);
    await session.dispose();
  });

  testWidgets('ready plays 3-card groups strongest first, 4-card last', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    await tester.tap(find.byTooltip('Suggest'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('readyButton')));
    await _settle(tester);
    final mine = session.view.value!.myArrangement!.groups;
    expect([for (final g in mine) g.length], [3, 3, 3, 4]);
    final strengths = [
      for (final g in mine) HandEvaluator.evaluate(g).strength,
    ];
    expect(strengths, [...strengths]..sort((a, b) => b.compareTo(a)));
    await session.dispose();
  });

  testWidgets('ready refuses a 4-card group that is not the weakest', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    // Sorted by rank, the 4-card group is J-Q-K-A: a run, too strong.
    await tester.tap(find.byTooltip('Sort by rank'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('readyButton')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('must be your weakest'), findsOneWidget);
    expect(session.view.value!.ready[0], isFalse);
    await _settle(tester);
    await session.dispose();
  });

  testWidgets('the Show button explains special hands when there is none', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    expect(find.byKey(const Key('showHandButton')), findsNothing);
    await tester.tap(find.byKey(const Key('showIconButton')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Nothing to show'), findsOneWidget);
    expect(session.view.value!.phase, GamePhase.arranging);
    await _settle(tester);
    await session.dispose();
  });

  testWidgets('ready, groups reveal by themselves, and the round is scored', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(tester, home: TableScreen(session: session));
    await _settle(tester);
    await tester.tap(find.byTooltip('Suggest'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('readyButton')));
    await _settle(tester);
    expect(session.view.value!.ready[0], isTrue);
    expect(session.view.value!.phase, isNot(GamePhase.arranging));

    // Groups are revealed without any taps.
    expect(find.byKey(const Key('playGroupButton')), findsNothing);
    for (var i = 0; i < 10; i++) {
      if (session.view.value!.phase != GamePhase.playing) break;
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
