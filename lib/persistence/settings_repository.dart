import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../bots/bot_strategy.dart';
import '../core/theme/table_themes.dart';
import '../game/scoring/cash_points.dart';

/// Background music tracks.
enum MusicTrack {
  himalaya,
  festival,
  calm;

  String get asset => switch (this) {
    MusicTrack.himalaya => 'audio/music_loop.ogg',
    _ => 'audio/music_$name.ogg',
  };
}

/// Sound effect sets. Classic files sit at the top of assets/audio/.
enum SoundSet {
  classic,
  soft,
  arcade;

  String get folder => this == SoundSet.classic ? 'audio/' : 'audio/$name/';
}

class AppSettings {
  const AppSettings({
    this.musicOn = true,
    this.sfxOn = true,
    this.musicVolume = 0.5,
    this.sfxVolume = 0.8,
    this.haptics = true,
    this.tableTheme = TableThemeId.emerald,
    this.cardBack = CardBackId.dhaka,
    this.languageCode,
    this.reducedMotion = false,
    this.playerName = '',
    this.difficulty = BotDifficulty.medium,
    this.musicTrack = MusicTrack.himalaya,
    this.soundSet = SoundSet.classic,
  });

  final bool musicOn;
  final bool sfxOn;
  final double musicVolume;
  final double sfxVolume;
  final bool haptics;
  final TableThemeId tableTheme;
  final CardBackId cardBack;

  /// null follows the device language.
  final String? languageCode;
  final bool reducedMotion;
  final String playerName;
  final BotDifficulty difficulty;
  final MusicTrack musicTrack;
  final SoundSet soundSet;

  AppSettings copyWith({
    bool? musicOn,
    bool? sfxOn,
    double? musicVolume,
    double? sfxVolume,
    bool? haptics,
    TableThemeId? tableTheme,
    CardBackId? cardBack,
    String? Function()? languageCode,
    bool? reducedMotion,
    String? playerName,
    BotDifficulty? difficulty,
    MusicTrack? musicTrack,
    SoundSet? soundSet,
  }) => AppSettings(
    musicOn: musicOn ?? this.musicOn,
    sfxOn: sfxOn ?? this.sfxOn,
    musicVolume: musicVolume ?? this.musicVolume,
    sfxVolume: sfxVolume ?? this.sfxVolume,
    haptics: haptics ?? this.haptics,
    tableTheme: tableTheme ?? this.tableTheme,
    cardBack: cardBack ?? this.cardBack,
    languageCode: languageCode != null ? languageCode() : this.languageCode,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    playerName: playerName ?? this.playerName,
    difficulty: difficulty ?? this.difficulty,
    musicTrack: musicTrack ?? this.musicTrack,
    soundSet: soundSet ?? this.soundSet,
  );

  Map<String, dynamic> toJson() => {
    'musicOn': musicOn,
    'sfxOn': sfxOn,
    'musicVolume': musicVolume,
    'sfxVolume': sfxVolume,
    'haptics': haptics,
    'tableTheme': tableTheme.name,
    'cardBack': cardBack.name,
    'languageCode': languageCode,
    'reducedMotion': reducedMotion,
    'playerName': playerName,
    'difficulty': difficulty.name,
    'musicTrack': musicTrack.name,
    'soundSet': soundSet.name,
  };

  /// Tolerant parsing: unknown or corrupt values fall back to defaults.
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    E pickEnum<E extends Enum>(String k, List<E> values, E fallback) {
      final v = j[k];
      for (final e in values) {
        if (e.name == v) return e;
      }
      return fallback;
    }

    double vol(String k, double fallback) {
      final v = j[k];
      return v is num ? v.toDouble().clamp(0.0, 1.0) : fallback;
    }

    return AppSettings(
      musicOn: pick('musicOn', d.musicOn),
      sfxOn: pick('sfxOn', d.sfxOn),
      musicVolume: vol('musicVolume', d.musicVolume),
      sfxVolume: vol('sfxVolume', d.sfxVolume),
      haptics: pick('haptics', d.haptics),
      tableTheme: pickEnum('tableTheme', TableThemeId.values, d.tableTheme),
      cardBack: pickEnum('cardBack', CardBackId.values, d.cardBack),
      languageCode: j['languageCode'] is String
          ? j['languageCode'] as String
          : null,
      reducedMotion: pick('reducedMotion', d.reducedMotion),
      playerName: pick('playerName', d.playerName),
      difficulty: pickEnum('difficulty', BotDifficulty.values, d.difficulty),
      musicTrack: pickEnum('musicTrack', MusicTrack.values, d.musicTrack),
      soundSet: pickEnum('soundSet', SoundSet.values, d.soundSet),
    );
  }
}

/// Persists settings, statistics and the in-progress offline match.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const _settingsKey = 'settings.v1';
  static const _savedMatchKey = 'savedMatch.v1';
  static const _statsKey = 'stats.v1';
  static const _clientIdKey = 'clientId.v1';
  static const _walletKey = 'wallet.v1';

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings s) =>
      _prefs.setString(_settingsKey, jsonEncode(s.toJson()));

  /// Raw JSON of the saved offline match, or null.
  Map<String, dynamic>? loadSavedMatch() {
    final raw = _prefs.getString(_savedMatchKey);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      // Corrupt save: discard rather than crash.
      _prefs.remove(_savedMatchKey);
      return null;
    }
  }

  Future<void> saveMatch(Map<String, dynamic> json) =>
      _prefs.setString(_savedMatchKey, jsonEncode(json));

  Future<void> clearSavedMatch() => _prefs.remove(_savedMatchKey);

  static const _lastRoomKey = 'online.lastRoom.v1';

  /// Code of the online room this player was last in, so the lobby can
  /// offer to rejoin after the app was closed mid-match.
  String? loadLastRoomCode() => _prefs.getString(_lastRoomKey);

  Future<void> saveLastRoomCode(String? code) => code == null
      ? _prefs.remove(_lastRoomKey)
      : _prefs.setString(_lastRoomKey, code);

  Wallet loadWallet() {
    final raw = _prefs.getString(_walletKey);
    if (raw == null) return const Wallet();
    try {
      return Wallet.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return const Wallet();
    }
  }

  Future<void> saveWallet(Wallet w) =>
      _prefs.setString(_walletKey, jsonEncode(w.toJson()));

  /// A random id identifying this install to Bluetooth hosts, so a dropped
  /// player can reclaim their seat.
  String clientId() {
    final existing = _prefs.getString(_clientIdKey);
    if (existing != null) return existing;
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    _prefs.setString(_clientIdKey, id);
    return id;
  }

  PlayerStats loadStats() {
    final raw = _prefs.getString(_statsKey);
    if (raw == null) return const PlayerStats();
    try {
      return PlayerStats.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const PlayerStats();
    }
  }

  Future<void> saveStats(PlayerStats s) =>
      _prefs.setString(_statsKey, jsonEncode(s.toJson()));
}

class PlayerStats {
  const PlayerStats({
    this.played = 0,
    this.won = 0,
    this.groupsWon = 0,
    this.sweeps = 0,
  });

  final int played;
  final int won;
  final int groupsWon;
  final int sweeps;

  PlayerStats add({
    bool played = false,
    bool won = false,
    int groups = 0,
    int sweeps = 0,
  }) => PlayerStats(
    played: this.played + (played ? 1 : 0),
    won: this.won + (won ? 1 : 0),
    groupsWon: groupsWon + groups,
    sweeps: this.sweeps + sweeps,
  );

  Map<String, dynamic> toJson() => {
    'played': played,
    'won': won,
    'groupsWon': groupsWon,
    'sweeps': sweeps,
  };

  factory PlayerStats.fromJson(Map<String, dynamic> j) => PlayerStats(
    played: j['played'] as int? ?? 0,
    won: j['won'] as int? ?? 0,
    groupsWon: j['groupsWon'] as int? ?? 0,
    sweeps: j['sweeps'] as int? ?? 0,
  );
}

/// The player's cash points (virtual, no money value).
class Wallet {
  const Wallet({
    this.balance = CashPoints.startingBalance,
    this.settledMatches = const [],
  });

  final int balance;

  /// Recently settled match ids, so a match is never paid out twice.
  final List<String> settledMatches;

  Wallet copyWith({int? balance, List<String>? settledMatches}) => Wallet(
    balance: balance ?? this.balance,
    settledMatches: settledMatches ?? this.settledMatches,
  );

  Map<String, dynamic> toJson() => {
    'balance': balance,
    'settledMatches': settledMatches,
  };

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
    balance: (json['balance'] as num).toInt(),
    settledMatches: (json['settledMatches'] as List? ?? const [])
        .cast<String>(),
  );
}
