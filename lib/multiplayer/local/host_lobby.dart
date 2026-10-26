import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../bots/bot_strategy.dart';
import '../../game/engine/game_engine.dart';
import '../../game/models/game_state.dart';
import '../../game/models/moves.dart';
import '../../game/models/player_view.dart';
import '../../game/state/authority_session.dart';
import 'line_connection.dart';

class LobbyPlayer {
  const LobbyPlayer({
    required this.clientId,
    required this.name,
    required this.connected,
  });

  final String clientId;
  final String name;
  final bool connected;
}

/// The host side of a local (Bluetooth) game. The host device is the single
/// authority: it deals, validates every move and scores. Each client only
/// ever receives its own [PlayerView].
///
/// Seats: 0 is the host; 1..3 are given to clients in join order. A client
/// that drops and reconnects with the same client id gets its seat back.
class HostLobby {
  HostLobby({
    required this.hostName,
    this.helloTimeout = const Duration(seconds: 10),
  });

  final String hostName;
  final Duration helloTimeout;

  /// Seats 1..3 (index 0 unused).
  final ValueNotifier<List<LobbyPlayer?>> players = ValueNotifier(
    List.filled(kSeatCount, null),
  );

  final Map<int, _SeatLink> _links = {};
  AuthorityGameSession? _session;
  bool _closed = false;

  bool get started => _session != null;

  int get joinedCount => players.value.where((p) => p != null).length;

  /// Hands a freshly accepted connection to the lobby.
  void accept(LineConnection conn) {
    if (_closed) {
      conn.close();
      return;
    }
    late StreamSubscription<String> sub;
    final timer = Timer(helloTimeout, () {
      sub.cancel();
      conn.close();
    });
    sub = conn.lines.listen((line) {
      final m = Wire.decode(line);
      if (m == null || m['t'] != 'hello') return;
      timer.cancel();
      // Stop handshake handling; the seat link takes this subscription
      // over (a connection's line stream can only be listened to once).
      sub.onData(null);
      _onHello(conn, sub, m);
    }, onDone: timer.cancel);
  }

  void _onHello(
    LineConnection conn,
    StreamSubscription<String> sub,
    Map<String, dynamic> m,
  ) {
    final id = m['id'] as String? ?? '';
    final name = (m['name'] as String? ?? '').trim();
    if (m['v'] != kProtocolVersion || id.isEmpty) {
      sub.cancel();
      conn.send(Wire.encode('error', {'code': 'version'}));
      conn.close();
      return;
    }
    final list = List<LobbyPlayer?>.of(players.value);
    var seat = list.indexWhere((p) => p?.clientId == id);
    if (seat < 0) {
      if (started) {
        sub.cancel();
        conn.send(Wire.encode('error', {'code': 'room-full'}));
        conn.close();
        return;
      }
      seat = list.indexWhere((p) => p == null, 1);
      if (seat < 0) {
        sub.cancel();
        conn.send(Wire.encode('error', {'code': 'room-full'}));
        conn.close();
        return;
      }
    }
    final displayName = name.isEmpty ? conn.peerName : name;
    list[seat] = LobbyPlayer(clientId: id, name: displayName, connected: true);
    players.value = list;
    final link = _links.putIfAbsent(seat, () => _SeatLink(seat));
    link.bind(conn, sub, onDrop: () => _onDrop(seat));
    link.sendRaw(Wire.encode('welcome', {'seat': seat}));
    _broadcastLobby();
    final s = _session;
    if (s != null) link.sendView(PlayerView.of(s.state, seat));
  }

  void _onDrop(int seat) {
    final list = List<LobbyPlayer?>.of(players.value);
    final p = list[seat];
    if (p == null) return;
    if (!started) {
      // Before the match, a dropped client simply frees the seat.
      list[seat] = null;
      _links.remove(seat)?.close();
    } else {
      list[seat] = LobbyPlayer(
        clientId: p.clientId,
        name: p.name,
        connected: false,
      );
    }
    players.value = list;
    _broadcastLobby();
  }

  void _broadcastLobby() {
    final names = [
      hostName,
      for (var i = 1; i < kSeatCount; i++) players.value[i]?.name,
    ];
    for (final l in _links.values) {
      l.sendRaw(Wire.encode('lobby', {'players': names, 'started': started}));
    }
  }

  /// Starts the match: empty seats get bots of [botDifficulty].
  AuthorityGameSession start({
    required ChuchulaGameEngine engine,
    required List<String> botNames,
    BotDifficulty botDifficulty = BotDifficulty.medium,
    BotTiming timing = const BotTiming(),
    BotRunner botRunner = isolateBotRunner,
    Duration disconnectGrace = const Duration(seconds: 60),
  }) {
    if (_session != null) return _session!;
    final seats = <SeatInfo>[SeatInfo(id: 'host', name: hostName, avatar: 0)];
    final bots = <int, BotStrategy>{};
    var botIndex = 0;
    for (var i = 1; i < kSeatCount; i++) {
      final p = players.value[i];
      if (p == null) {
        seats.add(
          SeatInfo(
            id: 'bot$i',
            name: botNames[botIndex++ % botNames.length],
            isBot: true,
            avatar: i,
          ),
        );
        bots[i] = BotStrategy.forDifficulty(botDifficulty);
      } else {
        seats.add(SeatInfo(id: p.clientId, name: p.name, avatar: i));
      }
    }
    final state = engine.startGame(
      GameSetup(
        matchId: 'bt-${DateTime.now().millisecondsSinceEpoch}',
        seats: seats,
      ),
    );
    _session = AuthorityGameSession(
      engine: engine,
      initialState: state,
      localSeat: 0,
      bots: bots,
      remoteSeats: Map.of(_links),
      timing: timing,
      botRunner: botRunner,
      disconnectGrace: disconnectGrace,
    );
    _broadcastLobby();
    return _session!;
  }

  Future<void> close() async {
    _closed = true;
    for (final l in _links.values) {
      l.sendRaw(Wire.encode('bye'));
      await l.close();
    }
    _links.clear();
    players.dispose();
  }
}

/// A seat's link to whichever connection currently serves it.
class _SeatLink implements RemoteSeatLink {
  _SeatLink(this.seat);

  final int seat;
  LineConnection? _conn;
  StreamSubscription<String>? _sub;
  final _moves = StreamController<GameMove>.broadcast();
  final ValueNotifier<bool> _connected = ValueNotifier(false);
  String? _lastView;

  void bind(
    LineConnection conn,
    StreamSubscription<String> sub, {
    required VoidCallback onDrop,
  }) {
    if (!identical(_sub, sub)) _sub?.cancel();
    _lastView = null; // a new connection always gets the current view
    final old = _conn;
    _conn = conn;
    if (old != null && !identical(old, conn)) old.close();
    _sub = sub
      ..onData(_onLine)
      ..onDone(() {
        if (identical(_conn, conn)) {
          _conn = null;
          _connected.value = false;
          onDrop();
        }
      })
      ..onError((Object _) {});
    _connected.value = true;
  }

  void _onLine(String line) {
    final m = Wire.decode(line);
    if (m == null) return;
    switch (m['t']) {
      case 'move':
        try {
          _moves.add(
            GameMove.fromJson((m['move'] as Map).cast<String, dynamic>()),
          );
        } catch (_) {
          sendError(RuleError.invalidSeat);
        }
      case 'ping':
        sendRaw(Wire.encode('pong'));
    }
  }

  void sendRaw(String line) {
    final c = _conn;
    if (c == null) return;
    c.send(line).catchError((Object _) {});
  }

  @override
  void sendView(PlayerView view) {
    final line = Wire.encode('view', {'view': view.toJson()});
    if (line == _lastView && _connected.value) return;
    _lastView = line;
    sendRaw(line);
  }

  @override
  void sendError(RuleError error) =>
      sendRaw(Wire.encode('error', {'code': error.name}));

  @override
  Stream<GameMove> get moves => _moves.stream;

  @override
  ValueListenable<bool> get isConnected => _connected;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _conn?.close();
    _conn = null;
  }
}
