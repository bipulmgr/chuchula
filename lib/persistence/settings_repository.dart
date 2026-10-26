import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../bots/bot_strategy.dart';
import '../core/theme/table_themes.dart';

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
