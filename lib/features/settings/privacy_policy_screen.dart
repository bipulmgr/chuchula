import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/localization/l10n.dart';
import '../../widgets/ornaments.dart';

/// Shows assets/legal/privacy_policy.md, the same text that is published
/// on the web for the store listings (docs/STORE_RELEASE.md).
class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  static const asset = 'assets/legal/privacy_policy.md';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(tableThemeProvider);
    final l = context.l10n;
    return Scaffold(
      backgroundColor: theme.feltEdge,
      appBar: AppBar(
        title: Text(l.privacyPolicy),
        backgroundColor: theme.surface,
        foregroundColor: theme.accentSoft,
      ),
      body: FeltBackground(
        theme: theme,
        child: FutureBuilder<String>(
          future: rootBundle.loadString(asset),
          builder: (context, snap) {
            final text = snap.data;
            if (text == null) {
              return Center(
                child: CircularProgressIndicator(color: theme.accent),
              );
            }
            return ListView(
              key: const Key('privacyPolicy'),
              padding: const EdgeInsets.all(20),
              children: [
                for (final block in _blocks(text))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: switch (block) {
                      (1, final t) => Text(
                        t,
                        style: TextStyle(
                          fontFamily: 'YatraOne',
                          fontSize: 26,
                          color: theme.accent,
                        ),
                      ),
                      (2, final t) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          t,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: theme.accentSoft,
                          ),
                        ),
                      ),
                      (_, final t) => SelectableText(
                        t,
                        style: TextStyle(color: theme.onSurface, height: 1.4),
                      ),
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Splits the small Markdown subset the policy uses into (level, text)
  /// blocks: 1 = title, 2 = heading, 0 = paragraph or bullet.
  static List<(int, String)> _blocks(String md) {
    final out = <(int, String)>[];
    final para = <String>[];
    void flush() {
      if (para.isNotEmpty) out.add((0, para.join(' ')));
      para.clear();
    }

    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('# ')) {
        flush();
        out.add((1, line.substring(2)));
      } else if (line.startsWith('## ')) {
        flush();
        out.add((2, line.substring(3)));
      } else if (line.startsWith('- ')) {
        flush();
        para.add('•  ${line.substring(2)}');
      } else if (line.isEmpty) {
        flush();
      } else {
        para.add(line.trim());
      }
    }
    flush();
    return out;
  }
}
