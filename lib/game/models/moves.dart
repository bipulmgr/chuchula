import '../rules/bonuses.dart';
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
      'arrange' => SubmitArrangement(
        seat,
        Arrangement.fromJson(json['arrangement']),
      ),
      'play' => PlayGroup(seat, json['group'] as int),
      'next' => StartNextRound(seat),
      'show' => ShowHand(
        seat,
        BonusType.values.where((b) => b.name == json['bonus']).firstOrNull,
      ),
      'passShow' => PassShow(seat),
      'closeShow' => CloseShow(seat),
      final t => throw FormatException('Unknown move type $t'),
    };
  }
}

/// Confirms a seat's arrangement ("Ready").
class SubmitArrangement extends GameMove {
  const SubmitArrangement(super.seat, this.arrangement);

  final Arrangement arrangement;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'arrange',
    'seat': seat,
    'arrangement': arrangement.toJson(),
  };
}

/// Reveals the seat's group for the group currently in play. [group] must
/// match the engine's current group; this makes repeated network events
/// idempotent (a duplicate is rejected rather than applied twice).
class PlayGroup extends GameMove {
  const PlayGroup(super.seat, this.group);

  final int group;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'play',
    'seat': seat,
    'group': group,
  };
}

/// Shows the seat's special hand (four of a kind, six pairs, three trails
/// or all thirteen ranks). During arranging this opens a short window in
/// which the other players may show theirs (or ends the match at once for
/// all thirteen ranks); during that window it is this seat's answer.
class ShowHand extends GameMove {
  const ShowHand(super.seat, [this.bonus]);

  /// The special the player says they hold. Only that kind is scored.
  /// Null shows every special in the hand.
  final BonusType? bonus;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'show',
    'seat': seat,
    if (bonus != null) 'bonus': bonus!.name,
  };
}

/// Declines to show a special hand while another player's show is open.
class PassShow extends GameMove {
  const PassShow(super.seat);

  @override
  Map<String, dynamic> toJson() => {'type': 'passShow', 'seat': seat};
}

/// Closes the show window once its time is up: seats that have not
/// answered count as passing. Sent by the authority (or, online, by any
/// client once the server agrees the time is up).
class CloseShow extends GameMove {
  const CloseShow(super.seat);

  @override
  Map<String, dynamic> toJson() => {'type': 'closeShow', 'seat': seat};
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
  fourCardTooStrong,
  wrongGroup,
  nothingToShow,
  alreadyAnswered,
  showStillOpen,
  matchOver,
}

class ValidationResult {
  const ValidationResult.ok() : error = null, detail = null;

  const ValidationResult.fail(RuleError this.error, [this.detail]);

  final RuleError? error;
  final String? detail;

  bool get isValid => error == null;

  @override
  String toString() => isValid
      ? 'ValidationResult.ok'
      : 'ValidationResult(${error!.name}: $detail)';
}

class InvalidMoveException implements Exception {
  InvalidMoveException(this.result);
  final ValidationResult result;

  @override
  String toString() =>
      'InvalidMoveException(${result.error?.name}: ${result.detail})';
}
