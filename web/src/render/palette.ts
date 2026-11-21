import { GroundKind } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';

/** An RGBA colour with channels 0..1. */
export type Rgba = readonly [number, number, number, number];

/** Parses #RRGGBB or #RRGGBBAA (design/tokens.json). */
export function rgba(hex: string, alpha = 1): Rgba {
  const v = hex.slice(1);
  const a = v.length === 8 ? parseInt(v.slice(6, 8), 16) / 255 : 1;
  return [parseInt(v.slice(0, 2), 16) / 255, parseInt(v.slice(2, 4), 16) / 255, parseInt(v.slice(4, 6), 16) / 255, a * alpha];
}

/** World colours and lighting from design/tokens.json (port of world_engine palette.dart). */
export interface Palette {
  land: Rgba; water: Rgba; park: Rgba; plaza: Rgba; rail: Rgba;
  sidewalk: Rgba; asphalt: Rgba; alley: Rgba; marking: Rgba; centerLine: Rgba;
  bridgeDeck: Rgba; bridgeEdge: Rgba; tunnel: Rgba; landmark: Rgba;
  facades: Rgba[];
  roofLight: number; sunX: number; sunY: number; ambient: number;
  night: boolean;
}

export const dayPalette: Palette = {
  land: rgba(tokens.colorWorldDayLand), water: rgba(tokens.colorWorldDayWater), park: rgba(tokens.colorWorldDayPark),
  plaza: rgba(tokens.colorWorldDayPlaza), rail: rgba(tokens.colorWorldDayRail), sidewalk: rgba(tokens.colorWorldDaySidewalk),
  asphalt: rgba(tokens.colorWorldDayAsphalt), alley: rgba(tokens.colorWorldDayAlley), marking: rgba(tokens.colorWorldDayMarking),
  centerLine: rgba(tokens.colorWorldDayCenterLine), bridgeDeck: rgba(tokens.colorWorldDayBridgeDeck),
  bridgeEdge: rgba(tokens.colorWorldDayBridgeEdge), tunnel: rgba(tokens.colorWorldDayTunnel), landmark: rgba(tokens.colorWorldDayLandmark),
  facades: tokens.colorWorldDayFacades.map((c) => rgba(c)),
  roofLight: tokens.lightDayRoofLight, sunX: tokens.lightDaySunX, sunY: tokens.lightDaySunY, ambient: tokens.lightDayAmbient,
  night: false,
};

export const nightPalette: Palette = {
  land: rgba(tokens.colorWorldNightLand), water: rgba(tokens.colorWorldNightWater), park: rgba(tokens.colorWorldNightPark),
  plaza: rgba(tokens.colorWorldNightPlaza), rail: rgba(tokens.colorWorldNightRail), sidewalk: rgba(tokens.colorWorldNightSidewalk),
  asphalt: rgba(tokens.colorWorldNightAsphalt), alley: rgba(tokens.colorWorldNightAlley), marking: rgba(tokens.colorWorldNightMarking),
  centerLine: rgba(tokens.colorWorldNightCenterLine), bridgeDeck: rgba(tokens.colorWorldNightBridgeDeck),
  bridgeEdge: rgba(tokens.colorWorldNightBridgeEdge), tunnel: rgba(tokens.colorWorldNightTunnel), landmark: rgba(tokens.colorWorldNightLandmark),
  facades: tokens.colorWorldNightFacades.map((c) => rgba(c)),
  roofLight: tokens.lightNightRoofLight, sunX: tokens.lightNightSunX, sunY: tokens.lightNightSunY, ambient: tokens.lightNightAmbient,
  night: true,
};

export function groundColor(p: Palette, k: GroundKind): Rgba {
  switch (k) {
    case GroundKind.WATER: return p.water;
    case GroundKind.PARK: return p.park;
    case GroundKind.PLAZA: return p.plaza;
    case GroundKind.RAIL: return p.rail;
    default: return p.land;
  }
}
