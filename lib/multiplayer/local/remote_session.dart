import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game/models/game_state.dart';
import '../../game/models/moves.dart';
import '../../game/models/player_view.dart';
import '../../game/state/game_session.dart';
import 'line_connection.dart';

enum ClientStatus { connecting, lobby, playing, reconnecting, failed, closed }

/// The client side of a local (Bluetooth) game: shows the views the host
/// sends and forwards this player's moves for the host to validate.
class RemoteGameSession extends BaseGameSession {
  RemoteGameSession({
    required this.connect,
    required this.clientId,
    required this.playerName,
    this.maxReconnectAttempts = 5,
    this.reconnectDelay = const Duration(seconds: 2),
  }) {
    _open();
  }

  /// Opens a new connection to the host (used again to reconnect).
  final Future<LineConnection> Function() connect;
  final String clientId;
  final String playerName;
  final int maxReconnectAttempts;
  final Duration reconnectDelay;

  final ValueNotifier<ClientStatus> status = ValueNotifier(
    ClientStatus.connecting,
  );
  final ValueNotifier<List<String?>> lobby = ValueNotifier(
    List.filled(kSeatCount, null),
  );
  String? lastError;

  LineConnection? _conn;
  StreamSubscription<String>? _sub;
  int _seat = -1;
  int _attempts = 0;
  bool _closing = false;
  bool _recovering = false;

  @override
  int get localSeat => _seat < 0 ? 0 : _seat;

  @override
  bool get canStartNextRound => false;

  Future<void> _open() async {
    try {
      final c = await connect();
      if (disposed || _closing) {
        await c.close();
        return;
      }
      _conn = c;
      _sub = c.lines.listen(_onLine, onDone: _onDone, onError: (_) {});
      await c.send(
        Wire.encode('hello', {
          'v': kProtocolVersion,
          'id': clientId,
          'name': playerName,
        }),
      );
    } catch (e) {
      lastError = e.toString();
      _scheduleReconnect();
    }
  }

  void _onLine(String line) {
    final m = Wire.decode(line);
    if (m == null || disposed) return;
    switch (m['t']) {
      case 'welcome':
        _seat = m['seat'] as int;
        _attempts = 0;
        _markRestored();
        status.value = viewNotifier.value == null
            ? ClientStatus.lobby
            : ClientStatus.playing;
      case 'lobby':
        lobby.value = (m['players'] as List).cast<String?>();
      case 'view':
        try {
          final v = PlayerView.fromJson(
            (m['view'] as Map).cast<String, dynamic>(),
          );
          final current = viewNotifier.value;
          if (current == null ||
              v.matchId != current.matchId ||
              v.version >= current.version) {
            _markRestored();
            viewNotifier.value = v;
            connectionsNotifier.value = [
              for (var i = 0; i < kSeatCount; i++)
                i == v.mySeat
                    ? SeatConnection.local
                    : v.seats[i].isBot
                    ? SeatConnection.bot
                    : SeatConnection.connected,
            ];
          }
          status.value = ClientStatus.playing;
        } catch (e) {
          debugPrint('Bad view from host: $e');
        }
      case 'error':
        final code = m['code'] as String? ?? '';
        final err = RuleError.values.where((r) => r.name == code);
        if (err.isNotEmpty) {
          emit(MoveRejected(err.first));
        } else {
          lastError = code;
          _closing = true;
          status.value = ClientStatus.failed;
        }
      case 'bye':
        _closing = true;
        status.value = ClientStatus.closed;
    }
  }

  void _markRestored() {
    if (_recovering) {
      _recovering = false;
      emit(const ConnectionRestored());
    }
  }

  void _onDone() {
    _conn = null;
    if (disposed || _closing) return;
    emit(const ConnectionLost('host'));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (disposed || _closing) return;
    if (_attempts >= maxReconnectAttempts) {
      status.value = ClientStatus.failed;
      return;
    }
    _attempts++;
    _recovering = true;
    status.value = ClientStatus.reconnecting;
    Timer(reconnectDelay * _attempts, () {
      if (!disposed && !_closing) _open();
    });
  }

  Future<void> _send(GameMove move) async {
    final c = _conn;
    if (c == null) {
      emit(const ConnectionLost('host'));
      return;
    }
    await c.send(Wire.encode('move', {'move': move.toJson()}));
  }

  @override
  Future<void> submitArrangement(Arrangement arrangement) =>
      _send(SubmitArrangement(localSeat, arrangement));

  @override
  Future<void> playGroup() =>
      _send(PlayGroup(localSeat, viewNotifier.value?.groupIndex ?? 0));

  @override
  Future<void> showHand() => _send(ShowHand(localSeat));

  @override
  Future<void> startNextRound() async {}

  @override
  Future<void> dispose() async {
    _closing = true;
    await _sub?.cancel();
    await _conn?.close();
    status.dispose();
    lobby.dispose();
    await super.dispose();
  }
}
