import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../persistence/settings_repository.dart';

enum Sfx {
  deal,
  drag,
  snap,
  play,
  turn,
  button,
  win,
  lose,
  achievement,
  groupWin;

  String get asset => switch (this) {
    Sfx.groupWin => 'audio/group_win.ogg',
    _ => 'audio/$name.ogg',
  };
}

/// Plays background music and sound effects, honoring the mute switches
/// and volumes in [AppSettings]. Music pauses when the app is backgrounded.
abstract class AudioService {
  void apply(AppSettings settings);
  void play(Sfx sfx);
  void haptic([HapticKind kind = HapticKind.light]);
  void onPause();
  void onResume();
  Future<void> dispose();
}

enum HapticKind { light, medium, heavy, selection }

/// No-op implementation for tests and platforms without audio.
class SilentAudioService implements AudioService {
  final List<Sfx> played = [];
  AppSettings settings = const AppSettings();

  @override
  void apply(AppSettings s) => settings = s;
  @override
  void play(Sfx sfx) {
    if (settings.sfxOn) played.add(sfx);
  }

  @override
  void haptic([HapticKind kind = HapticKind.light]) {}
  @override
  void onPause() {}
  @override
  void onResume() {}
  @override
  Future<void> dispose() async {}
}

class AudioPlayersService implements AudioService {
  AudioPlayersService() {
    _music.setReleaseMode(ReleaseMode.loop);
    _music.setPlayerMode(PlayerMode.mediaPlayer);
  }

  final AudioPlayer _music = AudioPlayer(playerId: 'music');
  // A small pool so overlapping effects (dealing) do not cut each other off.
  final List<AudioPlayer> _pool = List.generate(
    4,
    (i) => AudioPlayer(playerId: 'sfx$i')..setPlayerMode(PlayerMode.lowLatency),
  );
  int _next = 0;
  AppSettings _settings = const AppSettings();
  bool _paused = false;
  bool _musicStarted = false;
  DateTime _lastDeal = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void apply(AppSettings s) {
    _settings = s;
    _music.setVolume(s.musicVolume * 0.6);
    for (final p in _pool) {
      p.setVolume(s.sfxVolume);
    }
    _syncMusic();
  }

  void _syncMusic() {
    final shouldPlay = _settings.musicOn && !_paused;
    _guard(() async {
      if (shouldPlay && !_musicStarted) {
        _musicStarted = true;
        await _music.play(AssetSource('audio/music_loop.ogg'));
      } else if (shouldPlay) {
        await _music.resume();
      } else {
        await _music.pause();
      }
    });
  }

  @override
  void play(Sfx sfx) {
    if (!_settings.sfxOn || _paused || _settings.sfxVolume <= 0) return;
    if (sfx == Sfx.deal) {
      // Throttle rapid deal ticks.
      final now = DateTime.now();
      if (now.difference(_lastDeal).inMilliseconds < 45) return;
      _lastDeal = now;
    }
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    _guard(() async {
      await p.stop();
      await p.play(AssetSource(sfx.asset), volume: _settings.sfxVolume);
    });
  }

  @override
  void haptic([HapticKind kind = HapticKind.light]) {
    if (!_settings.haptics) return;
    switch (kind) {
      case HapticKind.light:
        HapticFeedback.lightImpact();
      case HapticKind.medium:
        HapticFeedback.mediumImpact();
      case HapticKind.heavy:
        HapticFeedback.heavyImpact();
      case HapticKind.selection:
        HapticFeedback.selectionClick();
    }
  }

  @override
  void onPause() {
    _paused = true;
    _syncMusic();
  }

  @override
  void onResume() {
    _paused = false;
    _syncMusic();
  }

  /// Audio failures (focus loss, missing codec) must never crash the game.
  void _guard(Future<void> Function() f) {
    unawaited(
      f().catchError((Object e) {
        debugPrint('Audio error: $e');
      }),
    );
  }

  @override
  Future<void> dispose() async {
    await _music.dispose();
    for (final p in _pool) {
      await p.dispose();
    }
  }
}
