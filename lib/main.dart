import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ads/rewarded_ads.dart';
import 'app/app.dart';
import 'app/providers.dart';
import 'audio/audio_service.dart';
import 'persistence/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  final store = await LocalStore.open();
  final audio = AudioPlayersService();
  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        audioServiceProvider.overrideWithValue(audio),
        rewardedAdsProvider.overrideWithValue(platformRewardedAds()),
      ],
      child: const _Lifecycle(child: ChuchulaApp()),
    ),
  );
}

/// Pauses music when the app goes to the background.
class _Lifecycle extends ConsumerStatefulWidget {
  const _Lifecycle({required this.child});
  final Widget child;

  @override
  ConsumerState<_Lifecycle> createState() => _LifecycleState();
}

class _LifecycleState extends ConsumerState<_Lifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final audio = ref.read(audioServiceProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        audio.onResume();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        audio.onPause();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
