import 'package:chuchula/app/providers.dart';
import 'package:chuchula/core/theme/table_themes.dart';
import 'package:chuchula/features/lobby/bluetooth_lobby_screen.dart';
import 'package:chuchula/features/lobby/online_lobby_screen.dart';
import 'package:chuchula/features/settings/settings_screen.dart';
import 'package:chuchula/features/tutorial/how_to_play_screen.dart';
import 'package:chuchula/persistence/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  testWidgets('home shows the title and every mode', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(find.text('चुचुला'), findsOneWidget);
    expect(find.byKey(const Key('playOfflineButton')), findsOneWidget);
    expect(find.byKey(const Key('playOnlineButton')), findsOneWidget);
    expect(find.byKey(const Key('bluetoothButton')), findsOneWidget);
    expect(find.text('Offline play is always available'), findsOneWidget);
  });

  testWidgets('home navigates to rules and settings', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rulesButton')));
    await tester.pumpAndSettle();
    expect(find.byType(HowToPlayScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('The 4-card group'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('The 4-card group'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('online without Firebase config explains the setup', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playOnlineButton')));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineLobbyScreen), findsOneWidget);
    expect(find.textContaining('docs/FIREBASE_SETUP.md'), findsOneWidget);
  });

  group('settings', () {
    testWidgets('music and sound toggles persist and reach the audio service', (
      tester,
    ) async {
      final env = await pumpApp(tester, home: const SettingsScreen());
      await tester.pumpAndSettle();
      expect(env.audio.settings.musicOn, isFalse);
      await tester.tap(find.byKey(const Key('musicToggle')));
      await tester.pumpAndSettle();
      expect(env.audio.settings.musicOn, isTrue);
      expect(env.store.loadSettings().musicOn, isTrue);

      await tester.tap(find.byKey(const Key('sfxToggle')));
      await tester.pumpAndSettle();
      expect(env.audio.settings.sfxOn, isFalse);
      // Muted effects are not played.
      env.audio.played.clear();
      await tester.tap(find.byKey(const Key('hapticsToggle')));
      await tester.pumpAndSettle();
      expect(env.audio.played, isEmpty);
      expect(env.store.loadSettings().haptics, isFalse);
    });

    testWidgets('music track, sound style and Suggest are saved', (
      tester,
    ) async {
      final env = await pumpApp(tester, home: const SettingsScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('musicTrack')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('musicTrack-festival')).last);
      await tester.pumpAndSettle();
      expect(env.audio.settings.musicTrack, MusicTrack.festival);
      expect(env.store.loadSettings().musicTrack, MusicTrack.festival);

      await tester.tap(find.byKey(const Key('soundSet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('soundSet-arcade')).last);
      await tester.pumpAndSettle();
      expect(env.store.loadSettings().soundSet, SoundSet.arcade);

      await tester.scrollUntilVisible(
        find.byKey(const Key('suggestToggle')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('suggestToggle')));
      await tester.pumpAndSettle();
      expect(env.store.loadSettings().showSuggest, isFalse);
    });

    testWidgets('choosing a theme recolors the app', (tester) async {
      final env = await pumpApp(tester, home: const SettingsScreen());
      await tester.pumpAndSettle();
      expect(env.container.read(tableThemeProvider).id, TableThemeId.emerald);
      await tester.scrollUntilVisible(
        find.byKey(const Key('theme-tihar')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme-tihar')));
      await tester.pumpAndSettle();
      expect(env.container.read(tableThemeProvider).id, TableThemeId.tihar);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, TableTheme.tihar.feltEdge);
      expect(env.store.loadSettings().tableTheme, TableThemeId.tihar);

      await tester.ensureVisible(find.byKey(const Key('back-lotus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('back-lotus')));
      await tester.pumpAndSettle();
      expect(env.store.loadSettings().cardBack, CardBackId.lotus);
    });

    testWidgets('switching language to Nepali translates the UI', (
      tester,
    ) async {
      await pumpApp(tester, home: const SettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('languageDropdown')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('languageDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('languageDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('नेपाली').last);
      await tester.pumpAndSettle();
      expect(find.text('सेटिङ'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
    });
  });

  group('bluetooth permissions', () {
    testWidgets('explains, requests, and handles denial', (tester) async {
      final bt = FakeBluetooth(granted: false, grantOnRequest: false);
      await pumpApp(tester, home: const BluetoothLobbyScreen(), bluetooth: bt);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('uses Bluetooth only to find'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('grantBluetooth')));
      await tester.pumpAndSettle();
      expect(bt.permissionRequests, 1);
      expect(find.textContaining('permission was denied'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(bt.settingsOpened, 1);
    });

    testWidgets('granted permission leads to host/join choice', (tester) async {
      final bt = FakeBluetooth(granted: false, grantOnRequest: true);
      await pumpApp(tester, home: const BluetoothLobbyScreen(), bluetooth: bt);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('grantBluetooth')));
      await tester.pumpAndSettle();
      expect(find.text('Host a game'), findsOneWidget);
      expect(find.text('Join a game'), findsOneWidget);
    });

    testWidgets('bluetooth off and unsupported states', (tester) async {
      await pumpApp(
        tester,
        home: const BluetoothLobbyScreen(),
        bluetooth: FakeBluetooth(granted: true, enabled: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bluetooth is turned off.'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(find.text('Host a game'), findsOneWidget);
    });

    testWidgets('joining lists paired phones', (tester) async {
      await pumpApp(
        tester,
        home: const BluetoothLobbyScreen(),
        bluetooth: FakeBluetooth(granted: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join a game'));
      await tester.pumpAndSettle();
      expect(find.text('Friend phone'), findsOneWidget);
    });
  });
}
