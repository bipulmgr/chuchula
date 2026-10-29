import 'dart:async';

import 'package:chuchula/ads/rewarded_ads.dart';
import 'package:chuchula/app/app.dart';
import 'package:chuchula/app/providers.dart';
import 'package:chuchula/audio/audio_service.dart';
import 'package:chuchula/multiplayer/bluetooth/bluetooth_platform.dart';
import 'package:chuchula/multiplayer/local/line_connection.dart';
import 'package:chuchula/persistence/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBluetooth implements BluetoothPlatform {
  FakeBluetooth({
    this.supported = true,
    this.enabled = true,
    this.granted = false,
    this.grantOnRequest = false,
    this.locationOff = false,
    this.failConnect = false,
    this.paired = const [
      BtDevice(name: 'Friend phone', address: '00:11', paired: true),
    ],
  });

  bool locationOff;
  bool failConnect;
  List<BtDevice> paired;
  int discoverableRequests = 0;
  int connectAttempts = 0;

  bool supported;
  bool enabled;
  bool granted;
  bool grantOnRequest;
  int permissionRequests = 0;
  int settingsOpened = 0;

  @override
  Future<BtState> state() async => BtState(
    supported: supported,
    enabled: enabled,
    permissionsGranted: granted,
    locationOff: locationOff,
  );

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    granted = grantOnRequest;
    return granted;
  }

  @override
  Future<bool> requestEnable() async => enabled = true;

  @override
  Future<bool> makeDiscoverable({int seconds = 300}) async {
    discoverableRequests++;
    return true;
  }

  @override
  Future<List<BtDevice>> pairedDevices() async => paired;

  final discoveredController = StreamController<BtDevice>.broadcast();
  @override
  Stream<BtDevice> get discovered => discoveredController.stream;
  @override
  Future<void> startDiscovery() async {}
  @override
  Future<void> stopDiscovery() async {}

  final hosted = StreamController<LineConnection>.broadcast();
  @override
  Stream<LineConnection> host() => hosted.stream;
  @override
  Future<void> stopHosting() async {}

  @override
  Future<LineConnection> connect(String address) {
    connectAttempts++;
    if (failConnect) {
      return Future.error(PlatformException(code: 'connect-failed'));
    }
    return Completer<LineConnection>().future;
  }

  @override
  Future<void> openAppSettings() async => settingsOpened++;

  @override
  Future<void> openLocationSettings() async => settingsOpened++;
}

/// Rewarded ads that finish instantly.
class FakeAds extends RewardedAds {
  FakeAds({this.supported = true, this.outcome = AdOutcome.rewarded});

  @override
  final bool supported;
  AdOutcome outcome;
  int shown = 0;
  int prepared = 0;

  @override
  Future<void> prepare() async => prepared++;

  @override
  Future<AdOutcome> show(BuildContext context) async {
    shown++;
    return outcome;
  }
}

class TestEnv {
  TestEnv(this.store, this.audio, this.bluetooth);
  final LocalStore store;
  final SilentAudioService audio;
  final FakeBluetooth bluetooth;
  late ProviderContainer container;
}

/// Pumps the app with in-memory storage, silent audio and fake Bluetooth.
Future<TestEnv> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  Widget? home,
  FakeBluetooth? bluetooth,
  RewardedAds ads = const NoRewardedAds(),
  bool reducedMotion = true,
}) async {
  // A phone-sized portrait screen.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    if (reducedMotion) 'settings.v1': '{"reducedMotion":true,"musicOn":false}',
    ...prefs,
  });
  final store = await LocalStore.open();
  final env = TestEnv(
    store,
    SilentAudioService(),
    bluetooth ?? FakeBluetooth(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        audioServiceProvider.overrideWithValue(env.audio),
        bluetoothPlatformProvider.overrideWithValue(env.bluetooth),
        rewardedAdsProvider.overrideWithValue(ads),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          env.container = ProviderScope.containerOf(context);
          return ChuchulaApp(home: home);
        },
      ),
    ),
  );
  await tester.pump();
  return env;
}
