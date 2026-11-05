import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/engine/game_engine.dart';
import '../../multiplayer/bluetooth/bluetooth_platform.dart';
import '../../multiplayer/local/host_lobby.dart';
import '../../multiplayer/local/remote_session.dart';
import '../../widgets/ornaments.dart';
import '../table/table_screen.dart';

enum _Stage {
  checking,
  unsupported,
  needPermission,
  denied,
  disabled,
  choose,
  hosting,
  joining,
}

class BluetoothLobbyScreen extends ConsumerStatefulWidget {
  const BluetoothLobbyScreen({super.key});

  @override
  ConsumerState<BluetoothLobbyScreen> createState() =>
      _BluetoothLobbyScreenState();
}

class _BluetoothLobbyScreenState extends ConsumerState<BluetoothLobbyScreen> {
  _Stage _stage = _Stage.checking;
  String? _error;
  bool _locationOff = false;

  // Hosting
  HostLobby? _lobby;
  StreamSubscription<dynamic>? _acceptSub;

  // Joining
  final List<BtDevice> _devices = [];
  StreamSubscription<BtDevice>? _discoverSub;
  RemoteGameSession? _client;
  bool _inGame = false;

  BluetoothPlatform get _bt => ref.read(bluetoothPlatformProvider);

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  Future<void> _teardown() async {
    await _acceptSub?.cancel();
    _acceptSub = null;
    await _discoverSub?.cancel();
    _discoverSub = null;
    try {
      await _bt.stopDiscovery();
      if (_lobby != null) await _bt.stopHosting();
    } catch (_) {}
    if (!_inGame) {
      await _lobby?.close();
      await _client?.dispose();
    }
    _lobby = null;
    _client = null;
  }

  Future<void> _check() async {
    try {
      final s = await _bt.state();
      if (!mounted) return;
      setState(() {
        _locationOff = s.locationOff;
        _stage = !s.supported
            ? _Stage.unsupported
            : !s.permissionsGranted
            ? _Stage.needPermission
            : !s.enabled
            ? _Stage.disabled
            : _Stage.choose;
      });
    } catch (e) {
      if (mounted) setState(() => _stage = _Stage.unsupported);
    }
  }

  Future<void> _askPermission() async {
    final ok = await _bt.requestPermissions();
    if (!mounted) return;
    if (ok) {
      await _check();
    } else {
      setState(() => _stage = _Stage.denied);
    }
  }

  Future<void> _enable() async {
    await _bt.requestEnable();
    await _check();
  }

  String get _name {
    final n = ref.read(settingsProvider).playerName.trim();
    return n.isEmpty ? context.l10n.defaultPlayerName : n;
  }

  Future<void> _host() async {
    final lobby = HostLobby(hostName: _name);
    _lobby = lobby;
    setState(() {
      _error = null;
      _stage = _Stage.hosting;
    });
    _acceptSub = _bt.host().listen(
      lobby.accept,
      onError: (Object e) {
        _acceptSub?.cancel();
        _acceptSub = null;
        _lobby = null;
        if (mounted) {
          setState(() {
            _error = context.l10n.btHostFailed(_describe(e));
            _stage = _Stage.choose;
          });
        }
        // After the rebuild, so the hosting panel no longer listens to it.
        WidgetsBinding.instance.addPostFrameCallback((_) => lobby.close());
      },
    );
    // Phones that were never paired can only find the host while it is
    // visible, so ask right away (one system dialog).
    try {
      await _bt.makeDiscoverable();
    } catch (_) {}
  }

  static String _describe(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : e.toString();

  Future<void> _startHostedGame() async {
    final lobby = _lobby!;
    final l = context.l10n;
    final session = lobby.start(
      engine: ChuchulaGameEngine(),
      botNames: l.botNames,
      botDifficulty: ref.read(settingsProvider).difficulty,
    );
    _inGame = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TableScreen(session: session, isOffline: false),
      ),
    );
    await session.dispose();
    await lobby.close();
    try {
      await _bt.stopHosting();
    } catch (_) {}
    _inGame = false;
    _lobby = null;
    if (mounted) setState(() => _stage = _Stage.choose);
  }

  Future<void> _join() async {
    // Retrying after a failed connection starts over from the device list.
    final old = _client;
    _client = null;
    setState(() {
      _stage = _Stage.joining;
      _devices.clear();
      _error = null;
    });
    await old?.dispose();
    try {
      final s = await _bt.state();
      _locationOff = s.locationOff;
      final paired = await _bt.pairedDevices();
      if (!mounted) return;
      setState(() => _devices.addAll(paired.where((d) => d.canHostGame)));
      _discoverSub ??= _bt.discovered.listen((d) {
        if (d.canHostGame && !_devices.contains(d) && mounted) {
          setState(() => _devices.add(d));
        }
      });
      await _bt.startDiscovery();
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  Future<void> _connectTo(BtDevice d) async {
    await _bt.stopDiscovery();
    final store = ref.read(localStoreProvider);
    await _client?.dispose();
    final client = RemoteGameSession(
      connect: () => _bt.connect(d.address),
      clientId: store.clientId(),
      playerName: _name,
    );
    setState(() {
      _client = client;
      _error = null;
    });
    client.view.addListener(() => _maybeOpenTable(client));
  }

  Future<void> _maybeOpenTable(RemoteGameSession client) async {
    if (_inGame || client.view.value == null || !mounted) return;
    _inGame = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TableScreen(session: client, isOffline: false),
      ),
    );
    await client.dispose();
    _inGame = false;
    _client = null;
    if (mounted) setState(() => _stage = _Stage.choose);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = ref.watch(tableThemeProvider);
    return Scaffold(
      backgroundColor: theme.feltEdge,
      appBar: AppBar(
        title: Text(l.bluetoothPlay),
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
              child: _body(theme, l),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(
    TableTheme theme,
    IconData icon,
    String text,
    List<Widget> actions,
  ) => GoldPanel(
    theme: theme,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: 48, color: theme.accent),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.4),
        ),
        for (final a in actions) ...[const SizedBox(height: 12), a],
      ],
    ),
  );

  Widget _body(TableTheme theme, AppLocalizations l) {
    switch (_stage) {
      case _Stage.checking:
        return Center(child: CircularProgressIndicator(color: theme.accent));
      case _Stage.unsupported:
        return _panel(theme, Icons.bluetooth_disabled, l.btUnsupported, []);
      case _Stage.needPermission:
        return _panel(theme, Icons.bluetooth, l.btPermissionRationale, [
          GoldButton(
            key: const Key('grantBluetooth'),
            theme: theme,
            label: l.grantPermission,
            onPressed: _askPermission,
          ),
        ]);
      case _Stage.denied:
        return _panel(theme, Icons.block, l.btPermissionDenied, [
          GoldButton(
            theme: theme,
            label: l.openSettings,
            onPressed: _bt.openAppSettings,
          ),
          GoldButton(
            theme: theme,
            label: l.retry,
            primary: false,
            onPressed: _check,
          ),
        ]);
      case _Stage.disabled:
        return _panel(theme, Icons.bluetooth_disabled, l.btDisabled, [
          GoldButton(theme: theme, label: l.turnOn, onPressed: _enable),
        ]);
      case _Stage.choose:
        return GoldPanel(
          theme: theme,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.btChooseRole, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              GoldButton(
                theme: theme,
                label: l.btHost,
                subtitle: l.btHostSub,
                icon: Icons.cell_tower,
                onPressed: _host,
              ),
              const SizedBox(height: 12),
              GoldButton(
                theme: theme,
                label: l.btJoin,
                subtitle: l.btJoinSub,
                icon: Icons.login,
                primary: false,
                onPressed: _join,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFFFB0A0))),
              ],
            ],
          ),
        );
      case _Stage.hosting:
        return _hosting(theme, l);
      case _Stage.joining:
        return _joining(theme, l);
    }
  }

  Widget _hosting(TableTheme theme, AppLocalizations l) {
    final lobby = _lobby!;
    return ValueListenableBuilder(
      valueListenable: lobby.players,
      builder: (context, players, _) => GoldPanel(
        theme: theme,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.btHostHint, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            GoldButton(
              theme: theme,
              label: l.btMakeVisible,
              icon: Icons.visibility,
              primary: false,
              onPressed: () => _bt.makeDiscoverable(),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(avatarIcons[0], color: theme.accent),
              title: Text(
                lobby.hostName,
                style: TextStyle(color: theme.onSurface),
              ),
              trailing: Text(l.hostLabel, style: TextStyle(color: theme.glow)),
            ),
            for (var i = 1; i < 4; i++)
              ListTile(
                leading: Icon(
                  players[i] == null ? Icons.event_seat : avatarIcons[i],
                  color: theme.accent,
                ),
                title: Text(
                  players[i]?.name ?? l.seatEmpty,
                  style: TextStyle(color: theme.onSurface),
                ),
              ),
            Text(
              '${l.btWaitingPlayers(lobby.joinedCount)} · ${l.fillWithBots}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            GoldButton(
              theme: theme,
              label: l.startGame,
              icon: Icons.play_arrow,
              onPressed: _startHostedGame,
            ),
          ],
        ),
      ),
    );
  }

  Widget _joining(TableTheme theme, AppLocalizations l) {
    final client = _client;
    if (client != null) {
      return ValueListenableBuilder(
        valueListenable: client.status,
        builder: (context, status, _) {
          final text = switch (status) {
            ClientStatus.connecting => l.connecting,
            ClientStatus.reconnecting => l.btReconnecting,
            ClientStatus.failed || ClientStatus.closed =>
              client.lastError == 'room-full' ? l.roomFull : l.btFailed,
            _ => l.btWaitingHost,
          };
          return GoldPanel(
            theme: theme,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status == ClientStatus.connecting ||
                    status == ClientStatus.reconnecting)
                  CircularProgressIndicator(color: theme.accent),
                const SizedBox(height: 12),
                Text(text, textAlign: TextAlign.center),
                ValueListenableBuilder(
                  valueListenable: client.lobby,
                  builder: (context, names, _) => Column(
                    children: [
                      for (final n in names)
                        if (n != null)
                          ListTile(
                            leading: Icon(Icons.person, color: theme.accent),
                            title: Text(
                              n,
                              style: TextStyle(color: theme.onSurface),
                            ),
                          ),
                    ],
                  ),
                ),
                if (status == ClientStatus.failed ||
                    status == ClientStatus.closed)
                  GoldButton(theme: theme, label: l.retry, onPressed: _join),
              ],
            ),
          );
        },
      );
    }
    return GoldPanel(
      theme: theme,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.btScanning,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: l.btScan,
                onPressed: _join,
                icon: Icon(Icons.refresh, color: theme.accentSoft),
              ),
            ],
          ),
          if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.btNoDevices, textAlign: TextAlign.center),
            ),
          if (_locationOff) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l.btLocationOff,
                key: const Key('btLocationOff'),
                textAlign: TextAlign.center,
              ),
            ),
            TextButton(
              onPressed: _bt.openLocationSettings,
              child: Text(
                l.openSettings,
                style: TextStyle(color: theme.accentSoft),
              ),
            ),
          ],
          for (final d in _devices)
            ListTile(
              leading: Icon(Icons.smartphone, color: theme.accent),
              title: Text(d.name, style: TextStyle(color: theme.onSurface)),
              subtitle: d.paired ? Text(l.btPaired) : null,
              onTap: () => _connectTo(d),
            ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFFFB0A0))),
        ],
      ),
    );
  }
}
