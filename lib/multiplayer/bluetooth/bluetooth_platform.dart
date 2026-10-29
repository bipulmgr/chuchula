import 'dart:async';

import 'package:flutter/services.dart';

import '../local/line_connection.dart';

class BtDevice {
  const BtDevice({
    required this.name,
    required this.address,
    this.paired = false,
    this.kind = 'unknown',
  });

  final String name;
  final String address;
  final bool paired;

  /// 'phone', 'computer' (tablets often report this), 'unknown' or 'other'
  /// (headphones, watches, cars, TVs...).
  final String kind;

  /// Whether this could be a phone or tablet running Chuchula.
  bool get canHostGame => kind != 'other';

  factory BtDevice.fromMap(Map<dynamic, dynamic> m) => BtDevice(
    name: (m['name'] as String?)?.trim().isNotEmpty == true
        ? m['name'] as String
        : m['address'] as String,
    address: m['address'] as String,
    paired: m['paired'] as bool? ?? false,
    kind: m['kind'] as String? ?? 'unknown',
  );

  @override
  bool operator ==(Object other) =>
      other is BtDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

class BtState {
  const BtState({
    required this.supported,
    required this.enabled,
    required this.permissionsGranted,
    this.locationOff = false,
  });

  final bool supported;
  final bool enabled;
  final bool permissionsGranted;

  /// Android 11 and lower: discovery needs the Location switch on.
  final bool locationOff;
}

/// Bluetooth Classic (RFCOMM) bridge to the Kotlin implementation in
/// android/app/src/main/kotlin/.../BluetoothBridge.kt.
///
/// Topology: star. The host opens one RFCOMM server socket and accepts up
/// to three clients; clients connect only to the host. Android supports
/// several simultaneous RFCOMM links per device (typically up to 7), so a
/// four-player star is within normal limits, but very old or low-end
/// devices may struggle with three.
abstract class BluetoothPlatform {
  Future<BtState> state();

  /// Requests the runtime permissions this Android version needs. Returns
  /// whether all were granted.
  Future<bool> requestPermissions();

  /// Asks the user to turn Bluetooth on. Returns whether it is now on.
  Future<bool> requestEnable();

  /// Shows the system dialog to make this phone discoverable.
  Future<bool> makeDiscoverable({int seconds = 300});

  Future<List<BtDevice>> pairedDevices();

  /// Discovered devices stream (cleared on each start).
  Stream<BtDevice> get discovered;
  Future<void> startDiscovery();
  Future<void> stopDiscovery();

  /// Starts accepting clients. Each accepted client is delivered on the
  /// returned stream.
  Stream<LineConnection> host();
  Future<void> stopHosting();

  Future<LineConnection> connect(String address);

  Future<void> openAppSettings();

  Future<void> openLocationSettings();
}

class MethodChannelBluetooth implements BluetoothPlatform {
  MethodChannelBluetooth() {
    _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
  }

  static const _method = MethodChannel('chuchula/bluetooth');
  static const _events = EventChannel('chuchula/bluetooth/events');

  final _discovered = StreamController<BtDevice>.broadcast();
  StreamController<LineConnection>? _accepted;
  final Map<String, _ChannelConnection> _connections = {};

  void _onEvent(dynamic e) {
    if (e is! Map) return;
    switch (e['type']) {
      case 'discovered':
        _discovered.add(BtDevice.fromMap(e['device'] as Map));
      case 'accepted':
        final c = _ChannelConnection(
          e['id'] as String,
          e['name'] as String? ?? '',
        );
        _connections[c.id] = c;
        _accepted?.add(c);
      case 'line':
        _connections[e['id']]?._lines.add(e['data'] as String);
      case 'closed':
        _connections.remove(e['id'])?._remoteClosed();
    }
  }

  @override
  Future<BtState> state() async {
    final m = await _method.invokeMapMethod<String, dynamic>('state') ?? {};
    return BtState(
      supported: m['supported'] as bool? ?? false,
      enabled: m['enabled'] as bool? ?? false,
      permissionsGranted: m['permissions'] as bool? ?? false,
      locationOff: m['locationOff'] as bool? ?? false,
    );
  }

  @override
  Future<bool> requestPermissions() async =>
      await _method.invokeMethod<bool>('requestPermissions') ?? false;

  @override
  Future<bool> requestEnable() async =>
      await _method.invokeMethod<bool>('requestEnable') ?? false;

  @override
  Future<bool> makeDiscoverable({int seconds = 300}) async =>
      await _method.invokeMethod<bool>('makeDiscoverable', {
        'seconds': seconds,
      }) ??
      false;

  @override
  Future<List<BtDevice>> pairedDevices() async {
    final list = await _method.invokeListMethod<Map>('pairedDevices') ?? [];
    return [for (final m in list) BtDevice.fromMap(m)];
  }

  @override
  Stream<BtDevice> get discovered => _discovered.stream;

  @override
  Future<void> startDiscovery() => _method.invokeMethod('startDiscovery');

  @override
  Future<void> stopDiscovery() => _method.invokeMethod('stopDiscovery');

  @override
  Stream<LineConnection> host() {
    _accepted?.close();
    final accepted = _accepted = StreamController<LineConnection>.broadcast();
    // A failure to open the server socket (permission revoked, Bluetooth
    // switched off) reaches the lobby as a stream error.
    _method.invokeMethod<void>('startServer').catchError((Object e) {
      if (!accepted.isClosed) accepted.addError(e);
    });
    return accepted.stream;
  }

  @override
  Future<void> stopHosting() async {
    await _method.invokeMethod('stopServer');
    await _accepted?.close();
    _accepted = null;
  }

  @override
  Future<LineConnection> connect(String address) async {
    final m = await _method.invokeMapMethod<String, dynamic>('connect', {
      'address': address,
    });
    if (m == null) throw PlatformException(code: 'connect-failed');
    final c = _ChannelConnection(
      m['id'] as String,
      m['name'] as String? ?? address,
    );
    _connections[c.id] = c;
    return c;
  }

  @override
  Future<void> openAppSettings() => _method.invokeMethod('openAppSettings');

  @override
  Future<void> openLocationSettings() =>
      _method.invokeMethod('openLocationSettings');
}

class _ChannelConnection implements LineConnection {
  _ChannelConnection(this.id, this.peerName);

  final String id;
  @override
  final String peerName;
  final _lines = StreamController<String>();
  bool _closed = false;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> send(String line) async {
    if (_closed) throw StateError('closed');
    await MethodChannelBluetooth._method.invokeMethod('send', {
      'id': id,
      'data': line,
    });
  }

  void _remoteClosed() {
    if (_closed) return;
    _closed = true;
    _lines.close();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _lines.close();
    await MethodChannelBluetooth._method.invokeMethod('disconnect', {'id': id});
  }
}
