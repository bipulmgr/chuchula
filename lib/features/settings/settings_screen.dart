import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../audio/audio_service.dart';
import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../persistence/settings_repository.dart';
import '../../game/models/card.dart';
import '../../widgets/card_widgets.dart';
import '../../widgets/ornaments.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final theme = ref.watch(tableThemeProvider);
    final n = ref.read(settingsProvider.notifier);
    final audio = ref.read(audioServiceProvider);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'YatraOne',
          fontSize: 20,
          color: theme.accent,
        ),
      ),
    );

    Widget toggle(String key, String label, bool value, ValueChanged<bool> f) =>
        SwitchListTile(
          key: Key(key),
          title: Text(label, style: TextStyle(color: theme.onSurface)),
          value: value,
          activeThumbColor: theme.accent,
          onChanged: (v) {
            f(v);
            audio.play(Sfx.button);
          },
        );

    Widget dropdown<T>(
      String key,
      String label,
      T value,
      List<T> values,
      String Function(T) name,
      ValueChanged<T> f,
    ) => ListTile(
      title: Text(label, style: TextStyle(color: theme.onSurface)),
      trailing: DropdownButton<T>(
        key: Key(key),
        value: value,
        dropdownColor: theme.surface,
        style: TextStyle(color: theme.onSurface, fontFamily: 'Mukta'),
        items: [
          for (final v in values)
            DropdownMenuItem(
              key: Key('$key-${(v as Enum).name}'),
              value: v,
              child: Text(name(v)),
            ),
        ],
        onChanged: (v) {
          if (v != null) f(v);
        },
      ),
    );

    Widget slider(
      String key,
      String label,
      double value,
      bool enabled,
      ValueChanged<double> f,
    ) => ListTile(
      title: Text(label, style: TextStyle(color: theme.onSurface)),
      subtitle: Slider(
        key: Key(key),
        value: value,
        onChanged: enabled ? f : null,
        onChangeEnd: (_) => audio.play(Sfx.button),
        activeColor: theme.accent,
      ),
    );

    return Scaffold(
      backgroundColor: theme.feltEdge,
      appBar: AppBar(
        title: Text(l.settings),
        backgroundColor: theme.surface,
        foregroundColor: theme.accentSoft,
      ),
      body: FeltBackground(
        theme: theme,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            header(l.soundSection),
            GoldPanel(
              theme: theme,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  toggle(
                    'musicToggle',
                    l.music,
                    s.musicOn,
                    (v) => n.update((x) => x.copyWith(musicOn: v)),
                  ),
                  dropdown(
                    'musicTrack',
                    l.musicTrack,
                    s.musicTrack,
                    MusicTrack.values,
                    l.trackName,
                    (v) => n.update((x) => x.copyWith(musicTrack: v)),
                  ),
                  slider(
                    'musicVolume',
                    l.musicVolume,
                    s.musicVolume,
                    s.musicOn,
                    (v) => n.update((x) => x.copyWith(musicVolume: v)),
                  ),
                  toggle(
                    'sfxToggle',
                    l.soundEffects,
                    s.sfxOn,
                    (v) => n.update((x) => x.copyWith(sfxOn: v)),
                  ),
                  dropdown(
                    'soundSet',
                    l.soundSet,
                    s.soundSet,
                    SoundSet.values,
                    l.soundSetName,
                    (v) {
                      n.update((x) => x.copyWith(soundSet: v));
                      audio.play(Sfx.groupWin);
                    },
                  ),
                  slider(
                    'sfxVolume',
                    l.sfxVolume,
                    s.sfxVolume,
                    s.sfxOn,
                    (v) => n.update((x) => x.copyWith(sfxVolume: v)),
                  ),
                  toggle(
                    'hapticsToggle',
                    l.haptics,
                    s.haptics,
                    (v) => n.update((x) => x.copyWith(haptics: v)),
                  ),
                ],
              ),
            ),
            header(l.appearanceSection),
            GoldPanel(
              theme: theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.tableTheme,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final id in TableThemeId.values)
                        _ThemeSwatch(
                          key: Key('theme-${id.name}'),
                          id: id,
                          label: l.themeName(id),
                          selected: s.tableTheme == id,
                          onTap: () =>
                              n.update((x) => x.copyWith(tableTheme: id)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.cardBack,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      for (final b in CardBackId.values)
                        _Choice(
                          key: Key('back-${b.name}'),
                          selected: s.cardBack == b,
                          theme: theme,
                          label: l.cardBackName(b),
                          onTap: () => n.update((x) => x.copyWith(cardBack: b)),
                          child: CardBack(width: 46, style: b, theme: theme),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CardFace(card: parseCards('AS').single, width: 46),
                      const SizedBox(width: 6),
                      CardFace(card: parseCards('KH').single, width: 46),
                      const SizedBox(width: 6),
                      CardFace(card: parseCards('10D').single, width: 46),
                    ],
                  ),
                ],
              ),
            ),
            header(l.gameSection),
            GoldPanel(
              theme: theme,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      l.language,
                      style: TextStyle(color: theme.onSurface),
                    ),
                    trailing: DropdownButton<String?>(
                      key: const Key('languageDropdown'),
                      value: s.languageCode,
                      dropdownColor: theme.surface,
                      style: TextStyle(
                        color: theme.onSurface,
                        fontFamily: 'Mukta',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l.systemLanguage),
                        ),
                        const DropdownMenuItem(
                          value: 'en',
                          child: Text('English'),
                        ),
                        const DropdownMenuItem(
                          value: 'ne',
                          child: Text('नेपाली'),
                        ),
                      ],
                      onChanged: (v) =>
                          n.update((x) => x.copyWith(languageCode: () => v)),
                    ),
                  ),
                  toggle(
                    'suggestToggle',
                    l.showSuggestSetting,
                    s.showSuggest,
                    (v) => n.update((x) => x.copyWith(showSuggest: v)),
                  ),
                  toggle(
                    'motionToggle',
                    l.reducedMotion,
                    s.reducedMotion,
                    (v) => n.update((x) => x.copyWith(reducedMotion: v)),
                  ),
                  _AdPrivacyTile(theme: theme),
                ],
              ),
            ),
            header(l.about),
            GoldPanel(
              theme: theme,
              child: Text(l.aboutBody, style: const TextStyle(height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final TableThemeId id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = TableTheme.of(id);
    return _Choice(
      selected: selected,
      theme: t,
      label: label,
      onTap: onTap,
      child: Container(
        width: 64,
        height: 44,
        decoration: BoxDecoration(
          gradient: t.feltGradient,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.accent, width: 1.5),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.selected,
    required this.theme,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final TableTheme theme;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? theme.glow : Colors.transparent,
                width: 2,
              ),
            ),
            child: child,
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

/// Lets players in consent regions change their ad choices (an AdMob
/// requirement). Hidden where no consent form applies.
class _AdPrivacyTile extends ConsumerStatefulWidget {
  const _AdPrivacyTile({required this.theme});

  final TableTheme theme;

  @override
  ConsumerState<_AdPrivacyTile> createState() => _AdPrivacyTileState();
}

class _AdPrivacyTileState extends ConsumerState<_AdPrivacyTile> {
  late final Future<bool> _required = ref
      .read(rewardedAdsProvider)
      .privacyOptionsRequired();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _required,
    builder: (context, snap) {
      if (snap.data != true) return const SizedBox.shrink();
      final l = context.l10n;
      return ListTile(
        key: const Key('adPrivacyTile'),
        leading: Icon(Icons.privacy_tip, color: widget.theme.accent),
        title: Text(
          l.adPrivacy,
          style: TextStyle(color: widget.theme.onSurface),
        ),
        subtitle: Text(l.adPrivacySub),
        onTap: () => ref.read(rewardedAdsProvider).showPrivacyOptions(),
      );
    },
  );
}
