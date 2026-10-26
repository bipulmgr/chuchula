// Cross-engine parity: builds fixtures from the Dart engine and checks them
// against functions/test-fixtures/parity.json, which the TypeScript engine
// (functions/src/test/parity.test.ts) must also reproduce exactly.
//
// Regenerate after an intentional rules change:
//   UPDATE_PARITY=1 flutter test test/parity/parity_fixtures_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:chuchula/bots/bot_strategy.dart';
import 'package:chuchula/game/engine/game_engine.dart';
import 'package:chuchula/game/engine/random_source.dart';
import 'package:chuchula/game/models/card.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/models/moves.dart';
import 'package:chuchula/game/models/player_view.dart';
import 'package:chuchula/game/rules/bonuses.dart';
import 'package:chuchula/game/rules/hand_evaluator.dart';
import 'package:chuchula/game/rules/rule_config.dart';
import 'package:flutter_test/flutter_test.dart';

const fixturePath = 'functions/test-fixtures/parity.json';

/// JSON with object keys sorted, so both engines serialize identically.
String canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k as String).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(canonical).join(',')}]';
  return jsonEncode(v);
}

/// 32-bit FNV-1a over UTF-16 code units (matches the TypeScript helper).
String fnv(String s) {
  var h = 0x811c9dc5;
  for (final u in s.codeUnits) {
    h ^= u;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

List<String> codes(List<PlayingCard> cs) => [for (final c in cs) c.code];

Map<String, Object?> evaluatorFixtures() {
  final r = SeededRandomSource(1);
  final groups = <List<PlayingCard>>[
    for (final s in [
      'AS KS QS',
      'AS 2S 3S',
      'AH 2C 3D',
      'AS KH QD',
      '2C 3C 4C',
      'KS QS JS',
      'AS AH AD',
      '2C 2D 2H',
      'AS AH KD',
      'AS KS 9S',
      '2C 3D 5H',
      'AS KS QS JS',
      'AS 2S 3S 4S',
      'AH 2C 3D 4S',
      'AS AH AD AC',
      '2C 2D 2H 2S',
      'AS AH AD KS',
      'AS AH KS KD',
      'AS AH KS QD',
      'AS KS QS 9S',
      'AS KH QD JC',
      '10H JH QH KH',
    ])
      parseCards(s),
    for (var i = 0; i < 300; i++) r.shuffled(fullDeck()).sublist(0, 3),
    for (var i = 0; i < 300; i++) r.shuffled(fullDeck()).sublist(0, 4),
  ];
  return {
    'groups': [
      for (final g in groups)
        {
          'cards': codes(g),
          'strength': HandEvaluator.evaluate(g).strength,
          'category': HandEvaluator.evaluate(g).category.name,
        },
    ],
  };
}

Map<String, Object?> bonusFixtures() {
  final r = SeededRandomSource(2);
  final hands = <List<PlayingCard>>[
    parseCards('AS AH AD AC KS KH KD KC 2C 3C 4C 5C 6C'),
    parseCards('AS AH KS KH QS QH JS JH 10S 10H 9S 9H 2C'),
    parseCards('AS AH AD KS KH KD QS QH QD 2C 3C 4C 5C'),
    parseCards('AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS'),
    parseCards('AS AH AD AC KS KH KD QS QH QD JS JH 2C'),
    for (var i = 0; i < 200; i++) r.shuffled(fullDeck()).sublist(0, 13),
  ];
  const rules = RuleConfig.standard;
  return {
    'hands': [
      for (final h in hands)
        {
          'cards': codes(h),
          'bonuses': [
            for (final b in BonusDetector.detect(h, rules)) b.toJson(),
          ],
        },
    ],
  };
}

List<int> seededDeck(SeededRandomSource r) => [
  for (final c in r.shuffled(fullDeck())) c.id,
];

/// Plays a full match with MediumBot arrangements. Records every move,
/// a hash of the state after it, some invalid moves with their errors,
/// and full checkpoints of state and views.
Map<String, Object?> matchFixture(int seed, RuleConfig rules) {
  final r = SeededRandomSource(seed);
  final decks = [for (var i = 0; i < 80; i++) seededDeck(r)];
  final engine = ChuchulaGameEngine(random: FixedDeckRandomSource(decks));
  var s = engine.startGame(
    GameSetup(
      matchId: 'parity-$seed',
      rules: rules,
      seats: [
        for (var i = 0; i < 4; i++)
          SeatInfo(id: 'p$i', name: 'Player $i', isBot: i > 0, avatar: i),
      ],
    ),
  );
  final steps = <Map<String, Object?>>[];
  final rejections = <Map<String, Object?>>[];
  final checkpoints = <Map<String, Object?>>[
    {'step': -1, 'state': s.toJson()},
  ];

  void tryInvalid(GameMove m) {
    final v = engine.validateMove(s, m);
    rejections.add({
      'afterStep': steps.length - 1,
      'move': m.toJson(),
      'error': v.error?.name,
    });
  }

  void apply(GameMove m) {
    s = engine.applyMove(s, m);
    steps.add({'move': m.toJson(), 'hash': fnv(canonical(s.toJson()))});
  }

  const bot = MediumBot();
  var checkpointRounds = 0;
  while (s.phase != GamePhase.matchOver) {
    switch (s.phase) {
      case GamePhase.arranging:
        tryInvalid(PlayGroup(0, 0));
        tryInvalid(const StartNextRound(1));
        var shown = false;
        for (var seat = 0; seat < 4; seat++) {
          // A seat with a special hand shows it, ending the round.
          if (ChuchulaGameEngine.showable(s, seat).isNotEmpty) {
            apply(ShowHand(seat));
            shown = true;
            break;
          }
          tryInvalid(ShowHand(seat));
          final a = bot.arrange(PlayerView.of(s, seat));
          // Weakest first, so the engine has to reorder (or keep) them.
          final sorted = Arrangement(
            a.groups.toList()..sort(
              (x, y) =>
                  HandEvaluator.evaluate(x)
                      .compareTo(HandEvaluator.evaluate(y)),
            ),
          );
          if (seat == 0) {
            tryInvalid(
              SubmitArrangement(
                seat,
                Arrangement(sorted.groups.reversed.toList()),
              ),
            );
            final other = s.hands[1].first;
            tryInvalid(
              SubmitArrangement(
                seat,
                Arrangement([
                  [other, ...sorted.groups[0].sublist(1)],
                  ...sorted.groups.sublist(1),
                ]),
              ),
            );
          }
          apply(SubmitArrangement(seat, sorted));
        }
        if (!shown) tryInvalid(SubmitArrangement(0, s.arrangements[0]!));
      case GamePhase.playing:
        final turn = s.turnSeat!;
        tryInvalid(PlayGroup((turn + 1) % 4, s.groupIndex));
        tryInvalid(PlayGroup(turn, s.groupIndex + 1));
        if (s.groupIndex == 2 && s.roundPlays[2].every((p) => p == null)) {
          checkpoints.add({
            'step': steps.length - 1,
            'views': [for (var i = 0; i < 4; i++) PlayerView.of(s, i).toJson()],
          });
        }
        apply(PlayGroup(turn, s.groupIndex));
      case GamePhase.roundOver:
        if (checkpointRounds++ < 2) {
          checkpoints.add({'step': steps.length - 1, 'state': s.toJson()});
        }
        tryInvalid(PlayGroup(0, 0));
        apply(const StartNextRound(2));
      case GamePhase.matchOver:
        break;
    }
  }
  tryInvalid(const StartNextRound(0));
  checkpoints.add({'step': steps.length - 1, 'state': s.toJson()});
  return {
    'seed': seed,
    'rules': rules.toJson(),
    'decks': decks,
    'steps': steps,
    'rejections': rejections,
    'checkpoints': checkpoints,
  };
}

Map<String, Object?> buildFixtures() => {
  'version': 1,
  'evaluator': evaluatorFixtures(),
  'bonuses': bonusFixtures(),
  'matches': [
    matchFixture(11, RuleConfig.standard),
    matchFixture(
      12,
      const RuleConfig(
        sweepReplacesGroupPoints: false,
        bonusesStackWithGroupPoints: false,
        strongestFirst: false,
        declareBonuses: false,
      ),
    ),
    matchFixture(
      13,
      const RuleConfig(targetScore: 12, targetIsExact: true, maxRounds: 15),
    ),
  ],
};

void main() {
  test('Dart engine matches the shared parity fixtures', () {
    final built = buildFixtures();
    final file = File(fixturePath);
    if (Platform.environment['UPDATE_PARITY'] == '1') {
      file.writeAsStringSync(jsonEncode(built));
      return;
    }
    expect(file.existsSync(), isTrue, reason: 'run with UPDATE_PARITY=1');
    final stored = jsonDecode(file.readAsStringSync());
    expect(canonical(built), canonical(stored));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
