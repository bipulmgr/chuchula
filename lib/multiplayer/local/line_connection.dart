import 'dart:async';
import 'dart:convert';

/// A bidirectional, newline-delimited text connection. Bluetooth RFCOMM
/// sockets implement it on device; [MemoryLineConnection] implements it in
/// tests, so the host/client protocol is tested without hardware.
abstract class LineConnection {
  String get peerName;

  /// Incoming lines. Completes when the connection closes.
  Stream<String> get lines;

  Future<void> send(String line);

  Future<void> close();
}

/// Protocol version; bump on incompatible message changes.
const int kProtocolVersion = 1;

/// Message envelope helpers. Every message is one JSON object per line
/// with a `t` (type) field.
class Wire {
  const Wire._();

  static String encode(String type, [Map<String, dynamic> body = const {}]) =>
      jsonEncode({'t': type, ...body});

  /// Returns null for malformed input (never throws on bad peers).
  static Map<String, dynamic>? decode(String line) {
    try {
      final v = jsonDecode(line);
      if (v is Map && v['t'] is String) return v.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }
}

/// In-memory connection pair for tests and simulations.
class MemoryLineConnection implements LineConnection {
  MemoryLineConnection._(this.peerName, this._in, this._out);

  static (MemoryLineConnection, MemoryLineConnection) pair({
    String aName = 'A',
    String bName = 'B',
  }) {
    final ab = StreamController<String>();
    final ba = StreamController<String>();
    final a = MemoryLineConnection._(bName, ba, ab);
    final b = MemoryLineConnection._(aName, ab, ba);
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  @override
  final String peerName;
  final StreamController<String> _in;
  final StreamController<String> _out;
  MemoryLineConnection? _peer;
  bool _closed = false;

  /// Lines sent by this side (for assertions).
  final List<String> sent = [];

  @override
  Stream<String> get lines => _in.stream;

  @override
  Future<void> send(String line) async {
    if (_closed) throw StateError('closed');
    sent.add(line);
    _out.add(line);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Not awaited: a single-subscription controller's close() only
    // completes once someone has listened.
    unawaited(_out.close());
    final p = _peer;
    if (p != null && !p._closed) {
      p._closed = true;
      unawaited(p._out.close());
    }
  }
}
