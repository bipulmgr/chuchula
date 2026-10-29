import 'package:chuchula/ads/rewarded_ads.dart';
import 'package:chuchula/app/providers.dart';
import 'package:chuchula/core/theme/table_themes.dart';
import 'package:chuchula/features/lobby/bluetooth_lobby_screen.dart';
import 'package:chuchula/features/lobby/online_lobby_screen.dart';
import 'package:chuchula/features/settings/settings_screen.dart';
import 'package:chuchula/features/tutorial/how_to_play_screen.dart';
import 'package:chuchula/multiplayer/bluetooth/bluetooth_platform.dart';
import 'package:chuchula/persistence/settings_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  testWidgets('iPhones get no Bluetooth button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playOnlineButton')), findsOneWidget);
      expect(find.byKey(const Key('bluetoothButton')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('home shows the title and every mode', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(find.text('चुचुला'), findsOneWidget);
    expect(find.byKey(const Key('playOfflineButton')), findsOneWidget);
    expect(find.byKey(const Key('playOnlineButton')), findsOneWidget);
    expect(find.byKey(const Key('bluetoothButton')), findsOneWidget);
    expect(find.text('Offline play is always available'), findsOneWidget);
  });

  group('cash points', () {
    testWidgets('home shows the balance and an ad adds 50', (tester) async {
      final ads = FakeAds();
      await pumpApp(tester, ads: ads);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('walletBalance'))).data,
        '100',
      );
      await tester.tap(find.byKey(const Key('watchAdButton')));
      await tester.pumpAndSettle();
      expect(ads.shown, 1);
      expect(
        tester.widget<Text>(find.byKey(const Key('walletBalance'))).data,
        '150',
      );
      expect(find.text('+50 cash points added!'), findsOneWidget);
    });

    testWidgets('home loads an ad in advance', (tester) async {
      final ads = FakeAds();
      await pumpApp(tester, ads: ads);
      await tester.pumpAndSettle();
      expect(ads.prepared, 1);
    });

    testWidgets('no fill says to try again', (tester) async {
      await pumpApp(tester, ads: FakeAds(outcome: AdOutcome.unavailable));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('watchAdButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No ad is available'), findsOneWidget);
    });

    testWidgets('the debug test ad pays only when watched to the end', (
      tester,
    ) async {
      final ads = DemoRewardedAds(length: const Duration(seconds: 2));
      await pumpApp(tester, ads: ads);
      await tester.pumpAndSettle();
      Future<String?> balance() async =>
          tester.widget<Text>(find.byKey(const Key('walletBalance'))).data;

      // Closed at once: nothing.
      await tester.tap(find.byKey(const Key('watchAdButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('demoAd')), findsOneWidget);
      expect(find.text('Reward in 2 s'), findsOneWidget);
      await tester.tap(find.byKey(const Key('closeDemoAd')));
      await tester.pumpAndSettle();
      expect(await balance(), '100');
      expect(find.textContaining('closed early'), findsOneWidget);

      // Watched to the end: +50.
      await tester.tap(find.byKey(const Key('watchAdButton')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Reward earned'), findsOneWidget);
      await tester.tap(find.byKey(const Key('closeDemoAd')));
      await tester.pumpAndSettle();
      expect(await balance(), '150');
      expect(find.text('+50 cash points added!'), findsOneWidget);
    });

    testWidgets('an ad closed early gives nothing', (tester) async {
      await pumpApp(tester, ads: FakeAds(outcome: AdOutcome.closedEarly));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('watchAdButton')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('walletBalance'))).data,
        '100',
      );
      expect(find.textContaining('closed early'), findsOneWidget);
    });

    testWidgets('without ads support the player is told why', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('watchAdButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('iPhone apps'), findsOneWidget);
    });

    testWidgets('below 50 a new match asks for an ad first', (tester) async {
      final ads = FakeAds();
      await pumpApp(tester, ads: ads, prefs: {'wallet.v1': '{"balance":30}'});
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playOfflineButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('needCashDialog')), findsOneWidget);
      await tester.tap(find.text('Watch an ad for +50'));
      await tester.pumpAndSettle();
      expect(ads.shown, 1);
      expect(
        tester.widget<Text>(find.byKey(const Key('walletBalance'))).data,
        '80',
      );
    });
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
    testWidgets('the privacy policy opens from Settings', (tester) async {
      await pumpApp(tester, home: const SettingsScreen());
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('privacyPolicyTile')),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacyPolicyTile')));
      await tester.pumpAndSettle();
      // The asset loads with real I/O.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chuchula privacy policy'), findsOneWidget);
      expect(find.text('Offline play'), findsOneWidget);
    });

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

    testWidgets('headphones and other gadgets are not listed', (tester) async {
      final bt = FakeBluetooth(
        granted: true,
        paired: const [
          BtDevice(name: 'Friend phone', address: '00:11', kind: 'phone'),
          BtDevice(name: 'Earbuds', address: '00:22', kind: 'other'),
        ],
      );
      await pumpApp(tester, home: const BluetoothLobbyScreen(), bluetooth: bt);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join a game'));
      await tester.pumpAndSettle();
      bt.discoveredController
        ..add(const BtDevice(name: 'Tablet', address: '00:33'))
        ..add(const BtDevice(name: 'Car kit', address: '00:44', kind: 'other'));
      await tester.pumpAndSettle();
      expect(find.text('Friend phone'), findsOneWidget);
      expect(find.text('Tablet'), findsOneWidget);
      expect(find.text('Earbuds'), findsNothing);
      expect(find.text('Car kit'), findsNothing);
    });

    testWidgets('Retry after a failed connection goes back to the list', (
      tester,
    ) async {
      final bt = FakeBluetooth(granted: true, failConnect: true);
      await pumpApp(tester, home: const BluetoothLobbyScreen(), bluetooth: bt);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join a game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friend phone'));
      // Five reconnect attempts with growing delays, then failure.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        find.text('Could not stay connected to the host.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Friend phone'), findsOneWidget);
      expect(find.text('Could not stay connected to the host.'), findsNothing);
    });

    testWidgets('hosting asks to make the phone visible', (tester) async {
      final bt = FakeBluetooth(granted: true);
      await pumpApp(tester, home: const BluetoothLobbyScreen(), bluetooth: bt);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Host a game'));
      await tester.pumpAndSettle();
      expect(bt.discoverableRequests, 1);
    });

    testWidgets('a host that cannot open its socket says why', (tester) async {
      final bt = FakeBluetooth(granted: true);
      await pumpApp(tester, home: const BluetoothLobbyScreen(), bluetooth: bt);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Host a game'));
      await tester.pumpAndSettle();
      bt.hosted.addError(PlatformException(code: 'bluetooth', message: 'off'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not start hosting: off'),
        findsOneWidget,
      );
      expect(find.text('Host a game'), findsOneWidget);
    });

    testWidgets('Android 11 with Location off gets a hint', (tester) async {
      final bt = FakeBluetooth(granted: true, locationOff: true);
      await pumpApp(tester, home: const BluetoothLobbyScreen(), bluetooth: bt);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join a game'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btLocationOff')), findsOneWidget);
    });
  });
}
