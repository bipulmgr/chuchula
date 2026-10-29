import 'dart:async';
import 'dart:convert';

import 'package:chuchula/bots/bot_strategy.dart';
import 'package:chuchula/game/engine/game_engine.dart';
import 'package:chuchula/game/engine/random_source.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/models/moves.dart';
import 'package:chuchula/game/state/authority_session.dart';
import 'package:chuchula/game/state/game_session.dart';
import 'package:chuchula/multiplayer/local/host_lobby.dart';
import 'package:chuchula/multiplayer/local/line_connection.dart';
import 'package:chuchula/multiplayer/local/remote_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'offline_match_test.dart' show playToEnd;

Future<void> pump([int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Simulates a host device accepting Bluetooth clients over in-memory
/// connections. Each `dial()` produces a fresh connection, like a new
/// RFCOMM socket.
class FakeRadio {
  FakeRadio(this.lobby);
  final HostLobby lobby;
  final List<MemoryLineConnection> clientEnds = [];

  Future<LineConnection> dial() async {
    final (client, host) = MemoryLineConnection.pair(
      aName: 'phone',
      bName: 'host',
    );
    clientEnds.add(client);
    lobby.accept(host);
    return client;
  }
}

void main() {
  test('clients join, get seats, and a full match completes', () async {
    final lobby = HostLobby(hostName: 'Host');
    final radio = FakeRadio(lobby);
    final c1 = RemoteGameSession(
      connect: radio.dial,
      clientId: 'id-1',
      playerName: 'Maya',
    );
    final c2 = RemoteGameSession(
      connect: radio.dial,
      clientId: 'id-2',
      playerName: 'Bikash',
    );
    await pump();
    expect(lobby.players.value[1]?.name, 'Maya');
    expect(lobby.players.value[2]?.name, 'Bikash');
    expect(lobby.players.value[3], isNull);
    expect(c1.lobby.value, ['Host', 'Maya', 'Bikash', null]);

    final host = lobby.start(
      engine: ChuchulaGameEngine(random: SeededRandomSource(31)),
      botNames: ['Bot'],
      timing: const BotTiming.instant(),
      botRunner: inlineBotRunner,
    );
    await pump();
    expect(c1.view.value!.mySeat, 1);
    expect(c2.view.value!.mySeat, 2);
    expect(host.state.seats[3].isBot, isTrue);

    // Run all three humans concurrently until the match ends.
    final results = await Future.wait([
      playToEnd(host),
      playToEnd(c1),
      playToEnd(c2),
    ]);
    for (final v in results) {
      expect(v.phase, GamePhase.matchOver);
      expect(v.result!.winnerSeat, results.first.result!.winnerSeat);
    }

    await c1.dispose();
    await c2.dispose();
    await host.dispose();
    await lobby.close();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('views sent to a client contain only that client\'s hand', () async {
    final lobby = HostLobby(hostName: 'Host');
    final (client, hostEnd) = MemoryLineConnection.pair();
    final received = <Map<String, dynamic>>[];
    client.lines.listen(
      (l) => received.add(jsonDecode(l) as Map<String, dynamic>),
    );
    lobby.accept(hostEnd);
    await client.send(
      Wire.encode('hello', {'v': kProtocolVersion, 'id': 'x', 'name': 'X'}),
    );
    await pump();
    final host = lobby.start(
      engine: ChuchulaGameEngine(random: SeededRandomSource(2)),
      botNames: ['B'],
      timing: const BotTiming.instant(),
      botRunner: inlineBotRunner,
    );
    await pump();
    final view = received.lastWhere((m) => m['t'] == 'view')['view'] as Map;
    final text = jsonEncode(view);
    // A seat that showed its special hand has revealed it on purpose.
    final shown = {
      for (final r in host.state.history)
        if (r.round == host.state.round) ?r.shownSeat,
    };
    for (var seat = 0; seat < 4; seat++) {
      if (seat == 1 || shown.contains(seat)) continue;
      for (final c in host.state.hands[seat]) {
        expect(
          text.contains('"${c.code}"'),
          isFalse,
          reason: 'seat $seat ${c.code}',
        );
      }
    }
    await host.dispose();
    await lobby.close();
  });

  test('host rejects moves for another seat and next-round requests', () async {
    final lobby = HostLobby(hostName: 'Host');
    final (client, hostEnd) = MemoryLineConnection.pair();
    final errors = <String>[];
    client.lines.listen((l) {
      final m = jsonDecode(l) as Map<String, dynamic>;
      if (m['t'] == 'error') errors.add(m['code'] as String);
    });
    lobby.accept(hostEnd);
    await client.send(
      Wire.encode('hello', {'v': kProtocolVersion, 'id': 'x', 'name': 'X'}),
    );
    await pump();
    final host = lobby.start(
      engine: ChuchulaGameEngine(random: SeededRandomSource(3)),
      botNames: ['B'],
      timing: const BotTiming.instant(),
      botRunner: inlineBotRunner,
    );
    await pump();
    // Seat 1 pretends to be seat 0.
    final fake = SubmitArrangement(
      0,
      Arrangement.fromOrderedCards(host.state.hands[0]),
    );
    await client.send(Wire.encode('move', {'move': fake.toJson()}));
    await client.send(
      Wire.encode('move', {'move': const StartNextRound(1).toJson()}),
    );
    await client.send('garbage that is not json');
    await pump();
    expect(errors, [RuleError.invalidSeat.name, RuleError.invalidSeat.name]);
    expect(host.state.isReady(0), isFalse);
    await host.dispose();
    await lobby.close();
  });

  test('a dropped client reconnects to the same seat and resumes', () async {
    final lobby = HostLobby(hostName: 'Host');
    final radio = FakeRadio(lobby);
    final c1 = RemoteGameSession(
      connect: radio.dial,
      clientId: 'same-id',
      playerName: 'Maya',
      // Long enough that the "reconnecting" state is observable even on a
      // busy machine, before the client redials.
      reconnectDelay: const Duration(milliseconds: 300),
    );
    await pump();
    final host = lobby.start(
      engine: ChuchulaGameEngine(random: SeededRandomSource(4)),
      botNames: ['B'],
      timing: const BotTiming.instant(),
      botRunner: inlineBotRunner,
    );
    await pump();
    final events = <SessionEvent>[];
    c1.events.listen(events.add);
    final hostEvents = <SessionEvent>[];
    host.events.listen(hostEvents.add);

    // Radio drops.
    await radio.clientEnds.last.close();
    await pump();
    expect(host.connections.value[1], SeatConnection.reconnecting);
    expect(lobby.players.value[1]!.connected, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await pump();
    expect(radio.clientEnds.length, 2, reason: 'client redialled');
    expect(lobby.players.value[1]!.connected, isTrue);
    expect(host.connections.value[1], SeatConnection.connected);
    expect(c1.view.value!.mySeat, 1);
    expect(events.whereType<ConnectionLost>(), isNotEmpty);
    expect(events.whereType<ConnectionRestored>(), isNotEmpty);
    expect(hostEvents.whereType<ConnectionLost>(), isNotEmpty);

    // The reconnected client can still act.
    await c1.submitArrangement(const MediumBot().arrange(c1.view.value!));
    await pump();
    expect(host.state.isReady(1), isTrue);
    await c1.dispose();
    await host.dispose();
    await lobby.close();
  });

  test('a client that never returns is replaced by a bot', () async {
    final lobby = HostLobby(hostName: 'Host');
    final (client, hostEnd) = MemoryLineConnection.pair();
    lobby.accept(hostEnd);
    await client.send(
      Wire.encode('hello', {'v': kProtocolVersion, 'id': 'gone', 'name': 'G'}),
    );
    await pump();
    final host = lobby.start(
      engine: ChuchulaGameEngine(random: SeededRandomSource(8)),
      botNames: ['B'],
      timing: const BotTiming.instant(),
      botRunner: inlineBotRunner,
      disconnectGrace: const Duration(milliseconds: 20),
    );
    await pump();
    await client.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await pump();
    expect(host.connections.value[1], SeatConnection.bot);
    expect(host.state.isReady(1), isTrue, reason: 'bot arranged for the seat');
    await host.dispose();
    await lobby.close();
  });

  test('fifth player and wrong protocol version are refused', () async {
    final lobby = HostLobby(hostName: 'Host');
    final codes = <String>[];
    Future<void> join(String id, {int v = kProtocolVersion}) async {
      final (client, hostEnd) = MemoryLineConnection.pair();
      client.lines.listen((l) {
        final m = jsonDecode(l) as Map<String, dynamic>;
        if (m['t'] == 'error') codes.add(m['code'] as String);
      });
      lobby.accept(hostEnd);
      await client.send(Wire.encode('hello', {'v': v, 'id': id, 'name': id}));
    }

    await join('a');
    await join('b');
    await join('c');
    await join('d');
    await join('e', v: 99);
    await pump();
    expect(lobby.joinedCount, 3);
    expect(codes, containsAll(['room-full', 'version']));
    await lobby.close();
  });

  test('silent connections are dropped after the hello timeout', () async {
    final lobby = HostLobby(
      hostName: 'Host',
      helloTimeout: const Duration(milliseconds: 10),
    );
    final (client, hostEnd) = MemoryLineConnection.pair();
    final done = Completer<void>();
    client.lines.listen((_) {}, onDone: done.complete);
    lobby.accept(hostEnd);
    await done.future.timeout(const Duration(seconds: 1));
    expect(lobby.joinedCount, 0);
    await lobby.close();
  });
}
