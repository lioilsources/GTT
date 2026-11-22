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
    required this.pedestrian,
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
    required this.shadow,
    this.inks = const [],
  });

  final Color land, water, park, plaza, rail, pedestrian, sidewalk, asphalt, alley, marking, centerLine;
  final Color bridgeDeck, bridgeEdge, tunnel, landmark;
  final List<Color> facades;

  /// Roof brightness relative to the facade.
  final double roofLight;

  /// Horizontal direction towards the sun in world space (lights walls facing it).
  final double sunX;
  final double sunY;
  final double ambient;
  final bool night;

  /// Ground shadow under the player's car, traffic and patrols (specs/style.md "shadow").
  final Color shadow;

  /// Risograph inks of the city (`color.city.<id>.inks`), empty when the city has none.
  final List<Color> inks;

  Color ground(GroundKind k) => switch (k) {
    GroundKind.WATER => water,
    GroundKind.PARK => park,
    GroundKind.PLAZA => plaza,
    GroundKind.RAIL => rail,
    GroundKind.PEDESTRIAN => pedestrian,
    _ => land,
  };

  static final day = Palette._(
    land: const Color(Tokens.colorWorldDayLand),
    water: const Color(Tokens.colorWorldDayWater),
    park: const Color(Tokens.colorWorldDayPark),
    plaza: const Color(Tokens.colorWorldDayPlaza),
    rail: const Color(Tokens.colorWorldDayRail),
    pedestrian: const Color(Tokens.colorWorldDayPedestrian),
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
    shadow: const Color(Tokens.colorCarShadow),
  );

  static final _nyc = Palette._(
    land: const Color(Tokens.colorCityNycLand),
    water: const Color(Tokens.colorCityNycWater),
    park: const Color(Tokens.colorCityNycPark),
    plaza: const Color(Tokens.colorCityNycPlaza),
    rail: const Color(Tokens.colorCityNycRail),
    pedestrian: const Color(Tokens.colorCityNycPedestrian),
    sidewalk: const Color(Tokens.colorCityNycSidewalk),
    asphalt: const Color(Tokens.colorCityNycAsphalt),
    alley: const Color(Tokens.colorCityNycAlley),
    marking: const Color(Tokens.colorCityNycMarking),
    centerLine: const Color(Tokens.colorCityNycCenterLine),
    bridgeDeck: const Color(Tokens.colorCityNycBridgeDeck),
    bridgeEdge: const Color(Tokens.colorCityNycBridgeEdge),
    tunnel: const Color(Tokens.colorCityNycTunnel),
    landmark: const Color(Tokens.colorCityNycLandmark),
    facades: [for (final c in Tokens.colorCityNycFacades) Color(c)],
    roofLight: Tokens.lightDayRoofLight,
    sunX: Tokens.lightDaySunX,
    sunY: Tokens.lightDaySunY,
    ambient: Tokens.lightDayAmbient,
    night: false,
    shadow: const Color(Tokens.colorCityNycShadow),
  );

  static final _prague = Palette._(
    land: const Color(Tokens.colorCityPragueLand),
    water: const Color(Tokens.colorCityPragueWater),
    park: const Color(Tokens.colorCityPraguePark),
    plaza: const Color(Tokens.colorCityPraguePlaza),
    rail: const Color(Tokens.colorCityPragueRail),
    pedestrian: const Color(Tokens.colorCityPraguePedestrian),
    sidewalk: const Color(Tokens.colorCityPragueSidewalk),
    asphalt: const Color(Tokens.colorCityPragueAsphalt),
    alley: const Color(Tokens.colorCityPragueAlley),
    marking: const Color(Tokens.colorCityPragueMarking),
    centerLine: const Color(Tokens.colorCityPragueCenterLine),
    bridgeDeck: const Color(Tokens.colorCityPragueBridgeDeck),
    bridgeEdge: const Color(Tokens.colorCityPragueBridgeEdge),
    tunnel: const Color(Tokens.colorCityPragueTunnel),
    landmark: const Color(Tokens.colorCityPragueLandmark),
    facades: [for (final c in Tokens.colorCityPragueFacades) Color(c)],
    roofLight: Tokens.lightDayRoofLight,
    sunX: Tokens.lightDaySunX,
    sunY: Tokens.lightDaySunY,
    ambient: Tokens.lightDayAmbient,
    night: false,
    shadow: const Color(Tokens.colorCityPragueShadow),
    inks: [for (final c in Tokens.colorCityPragueInks) Color(c)],
  );

  /// Day palette of the city [cityId] (manifest id, specs/style.md): `color.city.<id>` with the
  /// shared `light.day`; a city without a skin gets [day]. Night stays [nightPalette] for all.
  static Palette forCity(String cityId) => switch (cityId) {
    'nyc' => _nyc,
    'prague' => _prague,
    _ => day,
  };

  static final nightPalette = Palette._(
    land: const Color(Tokens.colorWorldNightLand),
    water: const Color(Tokens.colorWorldNightWater),
    park: const Color(Tokens.colorWorldNightPark),
    plaza: const Color(Tokens.colorWorldNightPlaza),
    rail: const Color(Tokens.colorWorldNightRail),
    pedestrian: const Color(Tokens.colorWorldNightPedestrian),
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
    shadow: const Color(Tokens.colorCarShadow),
  );
}

/// Whether the risograph pass runs (specs/style.md "Risograf"): `style.risograph.<city>` is true,
/// it is day, and the city has inks to print with. Unknown cities never get it.
bool risographEnabled(TuningStyle style, String cityId, {required bool night}) {
  if (night) return false;
  final on = switch (cityId) {
    'nyc' => style.risograph.nyc,
    'prague' => style.risograph.prague,
    _ => false,
  };
  return on && Palette.forCity(cityId).inks.isNotEmpty;
}
