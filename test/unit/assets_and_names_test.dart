import 'dart:io';
import 'dart:math';

import 'package:chuchula/audio/audio_service.dart';
import 'package:chuchula/game/models/bot_names.dart';
import 'package:chuchula/persistence/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every sound set has every effect, and every track exists', () {
    for (final set in SoundSet.values) {
      for (final sfx in Sfx.values) {
        expect(
          File('assets/${sfx.asset(set)}').existsSync(),
          isTrue,
          reason: sfx.asset(set),
        );
      }
    }
    for (final t in MusicTrack.values) {
      expect(File('assets/${t.asset}').existsSync(), isTrue, reason: t.asset);
    }
  });

  test('bot names are different and change between games', () {
    final r = Random(1);
    final a = randomBotNames(3, random: r);
    expect(a.toSet().length, 3);
    final seen = {for (var i = 0; i < 20; i++) ...randomBotNames(3, random: r)};
    expect(seen.length, greaterThan(6));
    expect(
      randomBotNames(3, languageCode: 'ne').first.codeUnitAt(0),
      greaterThan(0x0900),
    );
  });

  test('new settings survive a JSON round trip', () {
    const s = AppSettings(musicTrack: MusicTrack.calm, soundSet: SoundSet.soft);
    final back = AppSettings.fromJson(s.toJson());
    expect(back.musicTrack, MusicTrack.calm);
    expect(back.soundSet, SoundSet.soft);
  });
}
