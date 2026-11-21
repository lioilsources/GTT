import 'dart:ui';

import 'package:shared_gen/citypack_pb.dart';
import 'package:shared_gen/shared_gen.dart';

/// World colours and lighting, read from design/tokens.json through shared_gen.
class Palette {
  const Palette._({
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

  final Color land, water, park, plaza, rail, sidewalk, asphalt, alley, marking, centerLine;
  final Color bridgeDeck, bridgeEdge, tunnel, landmark;
  final List<Color> facades;

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

  static final day = Palette._(
    land: const Color(Tokens.colorWorldDayLand),
    water: const Color(Tokens.colorWorldDayWater),
    park: const Color(Tokens.colorWorldDayPark),
    plaza: const Color(Tokens.colorWorldDayPlaza),
    rail: const Color(Tokens.colorWorldDayRail),
    sidewalk: const Color(Tokens.colorWorldDaySidewalk),
    asphalt: const Color(Tokens.colorWorldDayAsphalt),
    alley: const Color(Tokens.colorWorldDayAlley),
    marking: const Color(Tokens.colorWorldDayMarking),
    centerLine: const Color(Tokens.colorWorldDayCenterLine),
    bridgeDeck: const Color(Tokens.colorWorldDayBridgeDeck),
    bridgeEdge: const Color(Tokens.colorWorldDayBridgeEdge),
    tunnel: const Color(Tokens.colorWorldDayTunnel),
    landmark: const Color(Tokens.colorWorldDayLandmark),
    facades: [for (final c in Tokens.colorWorldDayFacades) Color(c)],
    roofLight: Tokens.lightDayRoofLight,
    sunX: Tokens.lightDaySunX,
    sunY: Tokens.lightDaySunY,
    ambient: Tokens.lightDayAmbient,
    night: false,
  );

  static final nightPalette = Palette._(
    land: const Color(Tokens.colorWorldNightLand),
    water: const Color(Tokens.colorWorldNightWater),
    park: const Color(Tokens.colorWorldNightPark),
    plaza: const Color(Tokens.colorWorldNightPlaza),
    rail: const Color(Tokens.colorWorldNightRail),
    sidewalk: const Color(Tokens.colorWorldNightSidewalk),
    asphalt: const Color(Tokens.colorWorldNightAsphalt),
    alley: const Color(Tokens.colorWorldNightAlley),
    marking: const Color(Tokens.colorWorldNightMarking),
    centerLine: const Color(Tokens.colorWorldNightCenterLine),
    bridgeDeck: const Color(Tokens.colorWorldNightBridgeDeck),
    bridgeEdge: const Color(Tokens.colorWorldNightBridgeEdge),
    tunnel: const Color(Tokens.colorWorldNightTunnel),
    landmark: const Color(Tokens.colorWorldNightLandmark),
    facades: [for (final c in Tokens.colorWorldNightFacades) Color(c)],
    roofLight: Tokens.lightNightRoofLight,
    sunX: Tokens.lightNightSunX,
    sunY: Tokens.lightNightSunY,
    ambient: Tokens.lightNightAmbient,
    night: true,
  );
}
