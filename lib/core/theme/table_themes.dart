import 'package:flutter/material.dart';

/// Visual themes for the table. Changing the theme recolors the felt,
/// ornaments, seat plates and highlights everywhere in the app.
enum TableThemeId { emerald, dashain, tihar, himalaya }

enum CardBackId { dhaka, mandala, lotus, classic }

class TableTheme {
  const TableTheme({
    required this.id,
    required this.feltCenter,
    required this.feltEdge,
    required this.rail,
    required this.accent,
    required this.accentSoft,
    required this.surface,
    required this.onSurface,
    required this.glow,
  });

  final TableThemeId id;
  final Color feltCenter;
  final Color feltEdge;

  /// Wooden/lacquer rail around the felt.
  final Color rail;

  /// Gold accent for borders, active seats and buttons.
  final Color accent;
  final Color accentSoft;

  /// Panels (seat plates, dialogs).
  final Color surface;
  final Color onSurface;

  /// Highlight for winning groups and turns.
  final Color glow;

  static const emerald = TableTheme(
    id: TableThemeId.emerald,
    feltCenter: Color(0xFF16714B),
    feltEdge: Color(0xFF07331F),
    rail: Color(0xFF3B2312),
    accent: Color(0xFFE0B354),
    accentSoft: Color(0xFFF3DFA2),
    surface: Color(0xFF0E2A1D),
    onSurface: Color(0xFFF8F1DC),
    glow: Color(0xFFFFD66B),
  );

  /// Deep vermilion inspired by Dashain tika and marigolds.
  static const dashain = TableTheme(
    id: TableThemeId.dashain,
    feltCenter: Color(0xFF9E2A2B),
    feltEdge: Color(0xFF4A0D12),
    rail: Color(0xFF2C1608),
    accent: Color(0xFFF2A93B),
    accentSoft: Color(0xFFFFD99A),
    surface: Color(0xFF3A0E12),
    onSurface: Color(0xFFFFF0DF),
    glow: Color(0xFFFFC14D),
  );

  /// Night of lights: indigo felt with diyo-gold highlights.
  static const tihar = TableTheme(
    id: TableThemeId.tihar,
    feltCenter: Color(0xFF2E2A6B),
    feltEdge: Color(0xFF0E0C2B),
    rail: Color(0xFF241509),
    accent: Color(0xFFFFB347),
    accentSoft: Color(0xFFFFE0A8),
    surface: Color(0xFF15133A),
    onSurface: Color(0xFFF6F0FF),
    glow: Color(0xFFFFA931),
  );

  /// Glacier blue of the Himalaya.
  static const himalaya = TableTheme(
    id: TableThemeId.himalaya,
    feltCenter: Color(0xFF1F5F7A),
    feltEdge: Color(0xFF0A2635),
    rail: Color(0xFF2F2A26),
    accent: Color(0xFFD9C27E),
    accentSoft: Color(0xFFEFE3BA),
    surface: Color(0xFF0D2430),
    onSurface: Color(0xFFEFF7FA),
    glow: Color(0xFFBFE8FF),
  );

  static TableTheme of(TableThemeId id) => switch (id) {
    TableThemeId.emerald => emerald,
    TableThemeId.dashain => dashain,
    TableThemeId.tihar => tihar,
    TableThemeId.himalaya => himalaya,
  };

  Gradient get feltGradient => RadialGradient(
    center: const Alignment(0, -0.1),
    radius: 1.05,
    colors: [feltCenter, Color.lerp(feltCenter, feltEdge, 0.55)!, feltEdge],
    stops: const [0, 0.6, 1],
  );
}

/// Seat avatar colors and icons.
const avatarColors = <Color>[
  Color(0xFFE0B354),
  Color(0xFF5BB0A6),
  Color(0xFFD9675B),
  Color(0xFF8E7CC3),
  Color(0xFF6FA8DC),
  Color(0xFFE69138),
];

const avatarIcons = <IconData>[
  Icons.temple_buddhist,
  Icons.landscape,
  Icons.local_florist,
  Icons.wb_sunny,
  Icons.nightlight_round,
  Icons.spa,
];
