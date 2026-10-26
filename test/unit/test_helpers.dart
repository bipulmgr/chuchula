import 'package:chuchula/game/engine/game_engine.dart';
import 'package:chuchula/game/engine/random_source.dart';
import 'package:chuchula/game/models/card.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/models/moves.dart';
import 'package:chuchula/game/rules/rule_config.dart';

const testSeats = [
  SeatInfo(id: 'p0', name: 'You'),
  SeatInfo(id: 'p1', name: 'Bot 1', isBot: true),
  SeatInfo(id: 'p2', name: 'Bot 2', isBot: true),
  SeatInfo(id: 'p3', name: 'Bot 3', isBot: true),
];

/// Builds a deck order so that, with the default dealer (seat 3), seat i
/// receives exactly `hands[i]`. Hands may be partial; remaining cards are
/// filled in from the unused cards.
List<int> deckFor(List<String> hands, {int dealer = 3}) {
  final parsed = [for (final h in hands) parseCards(h)];
  final used = {for (final h in parsed) ...h};
  final spare = [
    for (final c in fullDeck())
      if (!used.contains(c)) c,
  ];
  final full = <List<PlayingCard>>[];
  for (var i = 0; i < 4; i++) {
    final h = i < parsed.length ? List.of(parsed[i]) : <PlayingCard>[];
    while (h.length < 13) {
      h.add(spare.removeAt(0));
    }
    full.add(h);
  }
  final order = List<int>.filled(52, -1);
  for (var k = 0; k < 52; k++) {
    final seat = (dealer + 1 + k) % 4;
    order[k] = full[seat][k ~/ 4].id;
  }
  return order;
}

ChuchulaGameEngine fixedEngine(List<List<int>> decks) =>
    ChuchulaGameEngine(random: FixedDeckRandomSource(decks, seed: 7));

GameState start(ChuchulaGameEngine engine, {RuleConfig? rules}) =>
    engine.startGame(
      GameSetup(
        matchId: 'test',
        seats: testSeats,
        rules: rules ?? RuleConfig.standard,
      ),
    );

/// Arranges every seat as hand-order (sorted) chunks, or with [custom].
GameState arrangeAll(
  ChuchulaGameEngine engine,
  GameState s, {
  Map<int, String> custom = const {},
}) {
  for (var seat = 0; seat < 4; seat++) {
    final a = custom.containsKey(seat)
        ? Arrangement.fromOrderedCards(parseCards(custom[seat]!))
        : Arrangement.fromOrderedCards(s.hands[seat]);
    s = engine.applyMove(s, SubmitArrangement(seat, a));
  }
  return s;
}

GameState playRound(ChuchulaGameEngine engine, GameState s) {
  while (s.phase == GamePhase.playing) {
    s = engine.applyMove(s, PlayGroup(s.turnSeat!, s.groupIndex));
  }
  return s;
}
