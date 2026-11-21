import 'dart:ui';

import 'pb/citypack.pbenum.dart';

/// World colours. M0 ships one New York palette with a day and a night variant;
/// per-city style packs (style.yaml) replace it after the style board.
class Palette {
  const Palette({
    required this.land,
    required this.water,
    required this.park,
    required this.plaza,
    required this.rail,
    required this.sidewalk,
    required this.asphalt,
    required this.alley,
    required this.marking,
    required this.centerLine,
    required this.bridgeDeck,
    required this.bridgeEdge,
    required this.tunnel,
    required this.facades,
    required this.landmark,
    required this.roofLight,
    required this.sunX,
    required this.sunY,
    required this.ambient,
    required this.night,
  });

  final Color land;
  final Color water;
  final Color park;
  final Color plaza;
  final Color rail;
  final Color sidewalk;
  final Color asphalt;
  final Color alley;
  final Color marking;
  final Color centerLine;
  final Color bridgeDeck;
  final Color bridgeEdge;
  final Color tunnel;
  final List<Color> facades;
  final Color landmark;

  /// Roof brightness relative to the facade.
  final double roofLight;

  /// Horizontal direction towards the sun in world space (lights walls facing it).
  final double sunX;
  final double sunY;
  final double ambient;
  final bool night;

  Color ground(GroundKind k) => switch (k) {
        GroundKind.WATER => water,
        GroundKind.PARK => park,
        GroundKind.PLAZA => plaza,
        GroundKind.RAIL => rail,
        _ => land,
      };

  static const day = Palette(
    land: Color(0xFFE9E1D2),
    water: Color(0xFF4F8CC9),
    park: Color(0xFF79B35F),
    plaza: Color(0xFFDCCFB9),
    rail: Color(0xFF9C9087),
    sidewalk: Color(0xFFC9C1B4),
    asphalt: Color(0xFF55565E),
    alley: Color(0xFF8D8780),
    marking: Color(0xFFF2F2F2),
    centerLine: Color(0xFFF4C430),
    bridgeDeck: Color(0xFF6A6B73),
    bridgeEdge: Color(0xFF34343B),
    tunnel: Color(0xFF3B3B42),
    facades: [
      Color(0xFFD9C7A7), // limestone
      Color(0xFFB0684F), // brick
      Color(0xFF8FA9C4), // blue glass
      Color(0xFFBDBDB8), // concrete
      Color(0xFF6E8296), // dark glass
      Color(0xFFCFAE86), // sandstone
      Color(0xFF9A5A48), // brownstone
    ],
    landmark: Color(0xFFE8DCC2),
    roofLight: 1.12,
    sunX: -0.6,
    sunY: 0.8,
    ambient: 0.62,
    night: false,
  );

  static const nightPalette = Palette(
    land: Color(0xFF2A2C3A),
    water: Color(0xFF12223D),
    park: Color(0xFF1E3426),
    plaza: Color(0xFF3A3846),
    rail: Color(0xFF2D2B30),
    sidewalk: Color(0xFF4A4A57),
    asphalt: Color(0xFF1D1E25),
    alley: Color(0xFF34333B),
    marking: Color(0xFFB8B8C4),
    centerLine: Color(0xFFB8952A),
    bridgeDeck: Color(0xFF2B2C35),
    bridgeEdge: Color(0xFF111116),
    tunnel: Color(0xFF14141A),
    // Night facades stay bright: the night texture darkens walls and keeps lit windows.
    facades: [
      Color(0xFFE6DCF0),
      Color(0xFFE8C8C0),
      Color(0xFFC8D8FF),
      Color(0xFFDCDCE6),
      Color(0xFFB8C8E6),
      Color(0xFFE6D8D0),
      Color(0xFFD8B8B8),
    ],
    landmark: Color(0xFFFFF0D0),
    roofLight: 0.55,
    sunX: -0.6,
    sunY: 0.8,
    ambient: 0.8,
    night: true,
  );
}
