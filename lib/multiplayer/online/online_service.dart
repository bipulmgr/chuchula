import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../game/models/game_state.dart';
import '../../game/models/moves.dart';
import '../../game/models/player_view.dart';
import '../../game/state/game_session.dart';
import 'firebase_config.dart';

/// Public seat information stored on the room document.
class RoomSeat {
  const RoomSeat({
    this.uid,
    required this.name,
    this.avatar = 0,
    this.isBot = false,
    this.lastSeen = 0,
  });

  final String? uid;
  final String name;
  final int avatar;
  final bool isBot;
  final int lastSeen;

  bool get isEmpty => uid == null && !isBot;

  factory RoomSeat.fromJson(Map<String, dynamic> j) => RoomSeat(
    uid: j['uid'] as String?,
    name: j['name'] as String? ?? '',
    avatar: (j['avatar'] as num?)?.toInt() ?? 0,
    isBot: j['isBot'] as bool? ?? false,
    lastSeen: (j['lastSeen'] as num?)?.toInt() ?? 0,
  );
}

enum RoomStatus { waiting, playing, finished, abandoned }

class RoomInfo {
  const RoomInfo({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.status,
    required this.seats,
  });

  final String id;
  final String code;
  final String hostUid;
  final RoomStatus status;
  final List<RoomSeat> seats;

  factory RoomInfo.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? const {};
    return RoomInfo(
      id: s.id,
      code: d['code'] as String? ?? '',
      hostUid: d['hostUid'] as String? ?? '',
      status: RoomStatus.values.firstWhere(
        (r) => r.name == d['status'],
        orElse: () => RoomStatus.waiting,
      ),
      seats: [
        for (final seat in (d['seats'] as List? ?? const []))
          RoomSeat.fromJson((seat as Map).cast<String, dynamic>()),
      ],
    );
  }

  int seatOf(String uid) => seats.indexWhere((s) => s.uid == uid);
}

/// Errors surfaced to the lobby UI.
class OnlineException implements Exception {
  OnlineException(this.code, [this.message]);
  final String code;
  final String? message;

  @override
  String toString() => 'OnlineException($code: $message)';
}

/// Client side of online play. The client never deals, validates or scores:
/// it calls Cloud Functions, which run the same rules engine (ported to
/// TypeScript in functions/src) and write each player only their own view.
class OnlineService {
  OnlineService._(this._auth, this._db, this._functions);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  static OnlineService? _instance;

  static Future<OnlineService> connect() async {
    if (_instance != null) return _instance!;
    if (!FirebaseConfig.isConfigured) {
      throw OnlineException('not-configured');
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseConfig.options);
    }
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    final functions = FirebaseFunctions.instanceFor(
      region: FirebaseConfig.functionsRegion,
    );
    const emulator = FirebaseConfig.emulatorHost;
    if (emulator.isNotEmpty) {
      await auth.useAuthEmulator(emulator, 9099);
      db.useFirestoreEmulator(emulator, 8080);
      functions.useFunctionsEmulator(emulator, 5001);
    }
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    return _instance = OnlineService._(auth, db, functions);
  }

  String get uid => _auth.currentUser!.uid;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final r = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(r.data);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map ? details['reason'] as String? : null;
      throw OnlineException(reason ?? e.code, e.message);
    }
  }

  Future<String> createRoom(String name) async =>
      (await _call('createRoom', {'name': name}))['roomId'] as String;

  Future<String> joinRoom(String code, String name) async =>
      (await _call('joinRoom', {
            'code': code.trim().toUpperCase(),
            'name': name,
          }))['roomId']
          as String;

  Future<void> startMatch(String roomId) =>
      _call('startMatch', {'roomId': roomId});

  Future<void> leaveRoom(String roomId) =>
      _call('leaveRoom', {'roomId': roomId});

  Future<void> submitMove(String roomId, GameMove move) =>
      _call('submitMove', {'roomId': roomId, 'move': move.toJson()});

  Future<void> heartbeat(String roomId) =>
      _call('heartbeat', {'roomId': roomId});

  Stream<RoomInfo> watchRoom(String roomId) => _db
      .collection('rooms')
      .doc(roomId)
      .snapshots()
      .where((s) => s.exists)
      .map(RoomInfo.fromSnapshot);

  Stream<PlayerView> watchView(String roomId) => _db
      .collection('rooms')
      .doc(roomId)
      .collection('views')
      .doc(uid)
      .snapshots()
      .where((s) => s.exists && s.data()?['view'] is String)
      // Stored as JSON text: Firestore cannot hold nested arrays.
      .map(
        (s) => PlayerView.fromJson(
          (jsonDecode(s.data()!['view'] as String) as Map)
              .cast<String, dynamic>(),
        ),
      );
}

/// A [GameSession] backed by Firestore listeners and callable functions.
class OnlineGameSession extends BaseGameSession {
  OnlineGameSession(this.service, this.roomId) {
    _viewSub = service.watchView(roomId).listen((v) {
      // Ignore out-of-order snapshots (idempotent sync).
      final current = viewNotifier.value;
      if (current == null || v.version >= current.version) {
        viewNotifier.value = v;
      }
    }, onError: (Object e) => emit(ConnectionLost(e.toString())));
    _roomSub = service.watchRoom(roomId).listen(_onRoom);
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) => _beat());
    _beat();
  }

  final OnlineService service;
  final String roomId;
  late final StreamSubscription<PlayerView> _viewSub;
  late final StreamSubscription<RoomInfo> _roomSub;
  Timer? _heartbeat;
  bool _lost = false;

  /// A seat counts as reconnecting after this long without a heartbeat.
  static const staleAfter = Duration(seconds: 45);

  @override
  int get localSeat => viewNotifier.value?.mySeat ?? 0;

  @override
  bool get canStartNextRound => true;

  void _onRoom(RoomInfo room) {
    final now = DateTime.now().millisecondsSinceEpoch;
    connectionsNotifier.value = [
      for (var i = 0; i < kSeatCount; i++)
        if (i >= room.seats.length)
          SeatConnection.disconnected
        else if (room.seats[i].uid == service.uid)
          SeatConnection.local
        else if (room.seats[i].isBot)
          SeatConnection.bot
        else if (now - room.seats[i].lastSeen > staleAfter.inMilliseconds)
          SeatConnection.reconnecting
        else
          SeatConnection.connected,
    ];
  }

  Future<void> _beat() async {
    try {
      await service.heartbeat(roomId);
      if (_lost) {
        _lost = false;
        emit(const ConnectionRestored());
      }
    } catch (e) {
      if (!_lost) {
        _lost = true;
        emit(ConnectionLost(e.toString()));
      }
    }
  }

  Future<void> _send(GameMove move) async {
    try {
      await service.submitMove(roomId, move);
    } on OnlineException catch (e) {
      final err = RuleError.values.where((r) => r.name == e.code);
      if (err.isNotEmpty) {
        emit(MoveRejected(err.first));
      } else {
        emit(ConnectionLost(e.message ?? e.code));
      }
    } catch (e) {
      debugPrint('submitMove failed: $e');
      emit(ConnectionLost(e.toString()));
    }
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
  Future<void> startNextRound() => _send(StartNextRound(localSeat));

  @override
  void onResume() => _beat();

  @override
  Future<void> dispose() async {
    _heartbeat?.cancel();
    await _viewSub.cancel();
    await _roomSub.cancel();
    await super.dispose();
  }
}
