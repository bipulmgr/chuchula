import 'dart:async';

import 'package:flutter/foundation.dart';

import '../rules/bonuses.dart';
import '../models/game_state.dart';
import '../models/moves.dart';
import '../models/player_view.dart';

enum SeatConnection { local, bot, connected, reconnecting, disconnected }

/// A one-shot notification the table can react to (sound, banner, haptic).
sealed class SessionEvent {
  const SessionEvent();
}

class MoveRejected extends SessionEvent {
  const MoveRejected(this.error);
  final RuleError error;
}

class ConnectionLost extends SessionEvent {
  const ConnectionLost(this.message);
  final String message;
}

class ConnectionRestored extends SessionEvent {
  const ConnectionRestored();
}

/// The table UI talks only to a [GameSession]. Offline, Bluetooth and online
/// play provide different implementations; the UI cannot tell them apart.
abstract class GameSession {
  /// The local player's view; null until the first state arrives.
  ValueListenable<PlayerView?> get view;

  /// Connection status of every seat.
  ValueListenable<List<SeatConnection>> get connections;

  Stream<SessionEvent> get events;

  /// Seats currently "thinking" (bots arranging), for UI indicators.
  ValueListenable<Set<int>> get thinking;

  int get localSeat;

  /// Whether this device may start the next round (the authority/host).
  bool get canStartNextRound;

  Future<void> submitArrangement(Arrangement arrangement);

  Future<void> playGroup();

  /// Shows this seat's special [bonus] (the best one when null). During
  /// arranging this opens a short window for the others to show theirs;
  /// while another player's show is open it is this seat's answer.
  Future<void> showHand([BonusType? bonus]);

  /// Declines to show a special while another player's show is open.
  Future<void> passShow();

  /// Called by the table when its show countdown runs out. The authority
  /// keeps its own clock, so most sessions ignore this; online play asks
  /// the server to close the window.
  Future<void> showWindowExpired() async {}

  Future<void> startNextRound();

  /// Called by the app lifecycle observer.
  void onPause() {}
  void onResume() {}

  Future<void> dispose();
}

/// Shared plumbing for session implementations.
abstract class BaseGameSession extends GameSession {
  final ValueNotifier<PlayerView?> viewNotifier = ValueNotifier(null);
  final ValueNotifier<List<SeatConnection>> connectionsNotifier = ValueNotifier(
    List.filled(kSeatCount, SeatConnection.connected),
  );
  final ValueNotifier<Set<int>> thinkingNotifier = ValueNotifier(const {});
  final StreamController<SessionEvent> eventController =
      StreamController.broadcast();

  bool disposed = false;

  @override
  ValueListenable<PlayerView?> get view => viewNotifier;

  @override
  ValueListenable<List<SeatConnection>> get connections => connectionsNotifier;

  @override
  ValueListenable<Set<int>> get thinking => thinkingNotifier;

  @override
  Stream<SessionEvent> get events => eventController.stream;

  void emit(SessionEvent e) {
    if (!disposed) eventController.add(e);
  }

  @override
  @mustCallSuper
  Future<void> dispose() async {
    disposed = true;
    await eventController.close();
    viewNotifier.dispose();
    connectionsNotifier.dispose();
    thinkingNotifier.dispose();
  }
}
