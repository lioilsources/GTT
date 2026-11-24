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
    this.roof,
    this.roofEdge,
    this.castShadow,
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

  /// Flat roof colour (`color.city.<id>.roof`, specs/style.md v2); null = facade × [roofLight].
  final Color? roof;

  /// Parapet band along the roof outline; null = no band. Used only together with [roof].
  final Color? roofEdge;

  /// Building cast shadow on the ground (with alpha); null = no cast shadows.
  final Color? castShadow;

  /// Style A flat roofs: both `roof` and `roofEdge` are set (otherwise roofs stay v1).
  bool get flatRoofs => roof != null && roofEdge != null;

  /// The wet look of rain (specs/weather.md): road, sidewalk and alley colours × (1 − [k]),
  /// everything else as it is. [k] = `weather.wet_darken` × the rain amount of the blend.
  Palette wet(double k) {
    if (k <= 0) return this;
    final f = (1 - k).clamp(0.0, 1.0);
    Color dark(Color c) => Color.from(alpha: c.a, red: c.r * f, green: c.g * f, blue: c.b * f);
    return Palette._(
      land: land,
      water: water,
      park: park,
      plaza: plaza,
      rail: rail,
      pedestrian: pedestrian,
      sidewalk: dark(sidewalk),
      asphalt: dark(asphalt),
      alley: dark(alley),
      marking: marking,
      centerLine: centerLine,
      bridgeDeck: bridgeDeck,
      bridgeEdge: bridgeEdge,
      tunnel: tunnel,
      facades: facades,
      landmark: landmark,
      roofLight: roofLight,
      sunX: sunX,
      sunY: sunY,
      ambient: ambient,
      night: night,
      shadow: shadow,
      inks: inks,
      roof: roof,
      roofEdge: roofEdge,
      castShadow: castShadow,
    );
  }

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
    roof: const Color(Tokens.colorCityNycRoof),
    roofEdge: const Color(Tokens.colorCityNycRoofEdge),
    castShadow: const Color(Tokens.colorCityNycCastShadow),
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

  static final _tokyo = Palette._(
    land: const Color(Tokens.colorCityTokyoLand),
    water: const Color(Tokens.colorCityTokyoWater),
    park: const Color(Tokens.colorCityTokyoPark),
    plaza: const Color(Tokens.colorCityTokyoPlaza),
    rail: const Color(Tokens.colorCityTokyoRail),
    pedestrian: const Color(Tokens.colorCityTokyoPedestrian),
    sidewalk: const Color(Tokens.colorCityTokyoSidewalk),
    asphalt: const Color(Tokens.colorCityTokyoAsphalt),
    alley: const Color(Tokens.colorCityTokyoAlley),
    marking: const Color(Tokens.colorCityTokyoMarking),
    centerLine: const Color(Tokens.colorCityTokyoCenterLine),
    bridgeDeck: const Color(Tokens.colorCityTokyoBridgeDeck),
    bridgeEdge: const Color(Tokens.colorCityTokyoBridgeEdge),
    tunnel: const Color(Tokens.colorCityTokyoTunnel),
    landmark: const Color(Tokens.colorCityTokyoLandmark),
    facades: [for (final c in Tokens.colorCityTokyoFacades) Color(c)],
    roofLight: Tokens.lightDayRoofLight,
    sunX: Tokens.lightDaySunX,
    sunY: Tokens.lightDaySunY,
    ambient: Tokens.lightDayAmbient,
    night: false,
    shadow: const Color(Tokens.colorCityTokyoShadow),
    roof: const Color(Tokens.colorCityTokyoRoof),
    roofEdge: const Color(Tokens.colorCityTokyoRoofEdge),
    castShadow: const Color(Tokens.colorCityTokyoCastShadow),
  );

  static final _moscow = Palette._(
    land: const Color(Tokens.colorCityMoscowLand),
    water: const Color(Tokens.colorCityMoscowWater),
    park: const Color(Tokens.colorCityMoscowPark),
    plaza: const Color(Tokens.colorCityMoscowPlaza),
    rail: const Color(Tokens.colorCityMoscowRail),
    pedestrian: const Color(Tokens.colorCityMoscowPedestrian),
    sidewalk: const Color(Tokens.colorCityMoscowSidewalk),
    asphalt: const Color(Tokens.colorCityMoscowAsphalt),
    alley: const Color(Tokens.colorCityMoscowAlley),
    marking: const Color(Tokens.colorCityMoscowMarking),
    centerLine: const Color(Tokens.colorCityMoscowCenterLine),
    bridgeDeck: const Color(Tokens.colorCityMoscowBridgeDeck),
    bridgeEdge: const Color(Tokens.colorCityMoscowBridgeEdge),
    tunnel: const Color(Tokens.colorCityMoscowTunnel),
    landmark: const Color(Tokens.colorCityMoscowLandmark),
    facades: [for (final c in Tokens.colorCityMoscowFacades) Color(c)],
    roofLight: Tokens.lightDayRoofLight,
    sunX: Tokens.lightDaySunX,
    sunY: Tokens.lightDaySunY,
    ambient: Tokens.lightDayAmbient,
    night: false,
    shadow: const Color(Tokens.colorCityMoscowShadow),
    roof: const Color(Tokens.colorCityMoscowRoof),
    roofEdge: const Color(Tokens.colorCityMoscowRoofEdge),
    castShadow: const Color(Tokens.colorCityMoscowCastShadow),
  );

  /// Day palette of the city [cityId] (manifest id, specs/style.md): `color.city.<id>` with the
  /// shared `light.day`; a city without a skin gets [day]. Night stays [nightPalette] for all.
  static Palette forCity(String cityId) => switch (cityId) {
    'nyc' => _nyc,
    'prague' => _prague,
    'tokyo' => _tokyo,
    'moscow' => _moscow,
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
  return style.risograph.toJson()[cityId] == true && Palette.forCity(cityId).inks.isNotEmpty;
}
