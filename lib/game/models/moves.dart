import 'game_state.dart';

/// A request from a seat to change the game state. Moves are validated by
/// `ChuchulaGameEngine` before they are applied.
sealed class GameMove {
  const GameMove(this.seat);

  final int seat;

  Map<String, dynamic> toJson();

  static GameMove fromJson(Map<String, dynamic> json) {
    final seat = json['seat'] as int;
    return switch (json['type']) {
      'arrange' =>
        SubmitArrangement(seat, Arrangement.fromJson(json['arrangement'])),
      'play' => PlayGroup(seat, json['group'] as int),
      'next' => StartNextRound(seat),
      final t => throw FormatException('Unknown move type $t'),
    };
  }
}

/// Confirms a seat's arrangement ("Ready").
class SubmitArrangement extends GameMove {
  const SubmitArrangement(super.seat, this.arrangement);

  final Arrangement arrangement;

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'arrange', 'seat': seat, 'arrangement': arrangement.toJson()};
}

/// Reveals the seat's group for the group currently in play. [group] must
/// match the engine's current group; this makes repeated network events
/// idempotent (a duplicate is rejected rather than applied twice).
class PlayGroup extends GameMove {
  const PlayGroup(super.seat, this.group);

  final int group;

  @override
  Map<String, dynamic> toJson() => {'type': 'play', 'seat': seat, 'group': group};
}

/// Deals the next round after the round summary.
class StartNextRound extends GameMove {
  const StartNextRound(super.seat);

  @override
  Map<String, dynamic> toJson() => {'type': 'next', 'seat': seat};
}

/// Machine-readable reasons a move or arrangement was rejected. The UI
/// localizes these codes.
enum RuleError {
  wrongPhase,
  notYourTurn,
  invalidSeat,
  alreadyReady,
  wrongGroupCount,
  wrongGroupSize,
  duplicateCard,
  cardNotOwned,
  missingCards,
  notAscending,
  wrongGroup,
  matchOver,
}

class ValidationResult {
  const ValidationResult.ok()
      : error = null,
        detail = null;

  const ValidationResult.fail(RuleError this.error, [this.detail]);

  final RuleError? error;
  final String? detail;

  bool get isValid => error == null;

  @override
  String toString() =>
      isValid ? 'ValidationResult.ok' : 'ValidationResult(${error!.name}: $detail)';
}

class InvalidMoveException implements Exception {
  InvalidMoveException(this.result);
  final ValidationResult result;

  @override
  String toString() => 'InvalidMoveException(${result.error?.name}: ${result.detail})';
}
