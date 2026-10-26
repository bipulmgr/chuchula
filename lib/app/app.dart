import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization/l10n.dart';
import '../features/home/home_screen.dart';
import 'providers.dart';

class ChuchulaApp extends ConsumerWidget {
  const ChuchulaApp({super.key, this.home});

  /// Overrides the first screen (tests).
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = ref.watch(tableThemeProvider);
    return MaterialApp(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      locale: settings.languageCode == null
          ? null
          : Locale(settings.languageCode!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeAnimationDuration: const Duration(milliseconds: 400),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Mukta',
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.accent,
          brightness: Brightness.dark,
          surface: theme.surface,
          primary: theme.accent,
        ),
        scaffoldBackgroundColor: theme.feltEdge,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          },
        ),
      ),
      home: home ?? const HomeScreen(),
    );
  }
}
