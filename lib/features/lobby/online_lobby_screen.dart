import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../multiplayer/online/firebase_config.dart';
import '../../multiplayer/online/online_service.dart';
import '../../widgets/ornaments.dart';
import '../table/table_screen.dart';

class OnlineLobbyScreen extends ConsumerStatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  ConsumerState<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends ConsumerState<OnlineLobbyScreen> {
  OnlineService? _service;
  String? _error;
  bool _busy = false;
  String? _roomId;
  RoomInfo? _room;
  StreamSubscription<RoomInfo>? _roomSub;
  bool _inGame = false;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (FirebaseConfig.isConfigured) _connect();
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await OnlineService.connect();
      if (mounted) setState(() => _service = s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _name {
    final n = ref.read(settingsProvider).playerName.trim();
    return n.isEmpty ? context.l10n.defaultPlayerName : n;
  }

  Future<void> _run(Future<String> Function() action) async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await action();
      _watch(id);
    } on OnlineException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'room-not-found' => l.roomNotFound,
          'room-full' => l.roomFull,
          _ => l.onlineError(e.message ?? e.code),
        };
      });
    } catch (e) {
      setState(() => _error = l.onlineError(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _watch(String roomId) {
    _roomSub?.cancel();
    _roomId = roomId;
    _roomSub = _service!.watchRoom(roomId).listen((room) {
      if (!mounted) return;
      setState(() => _room = room);
      if (room.status == RoomStatus.playing && !_inGame) _openTable(roomId);
    });
  }

  Future<void> _openTable(String roomId) async {
    _inGame = true;
    final session = OnlineGameSession(_service!, roomId);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TableScreen(session: session, isOffline: false),
      ),
    );
    await session.dispose();
    if (!mounted) return;
    setState(() {
      _inGame = false;
      _roomId = null;
      _room = null;
    });
    await _roomSub?.cancel();
  }

  Future<void> _leave() async {
    final id = _roomId;
    await _roomSub?.cancel();
    setState(() {
      _roomId = null;
      _room = null;
    });
    if (id != null) {
      try {
        await _service?.leaveRoom(id);
      } catch (_) {
        // Leaving is best-effort; the server times out idle seats anyway.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = ref.watch(tableThemeProvider);
    Widget body;
    if (!FirebaseConfig.isConfigured) {
      body = _Message(
        theme: theme,
        icon: Icons.cloud_off,
        text: l.onlineNotConfigured,
      );
    } else if (_service == null) {
      body = _busy
          ? _Message(
              theme: theme,
              icon: Icons.cloud_sync,
              text: l.connecting,
              busy: true,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Message(
                  theme: theme,
                  icon: Icons.cloud_off,
                  text: l.onlineError(_error ?? ''),
                ),
                const SizedBox(height: 12),
                GoldButton(theme: theme, label: l.retry, onPressed: _connect),
              ],
            );
    } else if (_room != null) {
      body = _waitingRoom(theme, l, _room!);
    } else {
      body = _menu(theme, l);
    }
    return Scaffold(
      backgroundColor: theme.feltEdge,
      appBar: AppBar(
        title: Text(l.onlineTitle),
        backgroundColor: theme.surface,
        foregroundColor: theme.accentSoft,
      ),
      body: FeltBackground(
        theme: theme,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu(TableTheme theme, AppLocalizations l) => GoldPanel(
    theme: theme,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoldButton(
          theme: theme,
          label: l.createRoom,
          icon: Icons.add_circle,
          onPressed: _busy
              ? null
              : () => _run(() => _service!.createRoom(_name)),
        ),
        const SizedBox(height: 18),
        Text(
          l.joinWithCode,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          style: TextStyle(
            color: theme.onSurface,
            letterSpacing: 4,
            fontSize: 20,
          ),
          decoration: InputDecoration(
            labelText: l.roomCode,
            labelStyle: TextStyle(color: theme.accentSoft),
          ),
        ),
        GoldButton(
          theme: theme,
          label: l.join,
          icon: Icons.login,
          primary: false,
          onPressed: _busy
              ? null
              : () => _run(() => _service!.joinRoom(_code.text, _name)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Color(0xFFFFB0A0))),
        ],
        if (_busy) ...[
          const SizedBox(height: 12),
          Center(child: CircularProgressIndicator(color: theme.accent)),
        ],
      ],
    ),
  );

  Widget _waitingRoom(TableTheme theme, AppLocalizations l, RoomInfo room) {
    final isHost = room.hostUid == _service!.uid;
    return GoldPanel(
      theme: theme,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.waitingRoom(room.code),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'YatraOne',
              fontSize: 26,
              color: theme.accent,
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: room.code));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.codeCopied)));
            },
            icon: Icon(Icons.copy, color: theme.accentSoft),
            label: Text(l.copyCode, style: TextStyle(color: theme.accentSoft)),
          ),
          Text(l.shareCode, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          for (var i = 0; i < 4; i++)
            ListTile(
              leading: Icon(
                i < room.seats.length && !room.seats[i].isEmpty
                    ? avatarIcons[room.seats[i].avatar % avatarIcons.length]
                    : Icons.event_seat,
                color: theme.accent,
              ),
              title: Text(
                i < room.seats.length && !room.seats[i].isEmpty
                    ? room.seats[i].name
                    : l.seatEmpty,
                style: TextStyle(color: theme.onSurface),
              ),
              trailing:
                  i < room.seats.length && room.seats[i].uid == room.hostUid
                  ? Text(l.hostLabel, style: TextStyle(color: theme.glow))
                  : null,
            ),
          const SizedBox(height: 6),
          Text(
            l.fillWithBots,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (isHost)
            GoldButton(
              theme: theme,
              label: l.startGame,
              icon: Icons.play_arrow,
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await _service!.startMatch(room.id);
                      } on OnlineException catch (e) {
                        setState(
                          () => _error = l.onlineError(e.message ?? e.code),
                        );
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
            )
          else
            Text(l.btWaitingHost, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          GoldButton(
            theme: theme,
            label: l.leave,
            primary: false,
            onPressed: _leave,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFFFB0A0))),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.theme,
    required this.icon,
    required this.text,
    this.busy = false,
  });

  final TableTheme theme;
  final IconData icon;
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) => GoldPanel(
    theme: theme,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        busy
            ? CircularProgressIndicator(color: theme.accent)
            : Icon(icon, size: 48, color: theme.accent),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.4),
        ),
      ],
    ),
  );
}
