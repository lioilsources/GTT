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
  land: Rgba; water: Rgba; park: Rgba; plaza: Rgba; pedestrian: Rgba; rail: Rgba;
  sidewalk: Rgba; asphalt: Rgba; alley: Rgba; marking: Rgba; centerLine: Rgba;
  bridgeDeck: Rgba; bridgeEdge: Rgba; tunnel: Rgba; landmark: Rgba;
  facades: Rgba[];
  /** Ground shadow under the player's car, traffic and patrols (specs/style.md `shadow`). */
  shadow: Rgba;
  /** Flat vector look (specs/style.md v2): roof, parapet band and building cast shadow; absent = v1. */
  roof?: Rgba;
  roofEdge?: Rgba;
  castShadow?: Rgba;
  roofLight: number; sunX: number; sunY: number; ambient: number;
  night: boolean;
}

export const dayPalette: Palette = {
  land: rgba(tokens.colorWorldDayLand), water: rgba(tokens.colorWorldDayWater), park: rgba(tokens.colorWorldDayPark),
  plaza: rgba(tokens.colorWorldDayPlaza), pedestrian: rgba(tokens.colorWorldDayPedestrian), rail: rgba(tokens.colorWorldDayRail), sidewalk: rgba(tokens.colorWorldDaySidewalk),
  asphalt: rgba(tokens.colorWorldDayAsphalt), alley: rgba(tokens.colorWorldDayAlley), marking: rgba(tokens.colorWorldDayMarking),
  centerLine: rgba(tokens.colorWorldDayCenterLine), bridgeDeck: rgba(tokens.colorWorldDayBridgeDeck),
  bridgeEdge: rgba(tokens.colorWorldDayBridgeEdge), tunnel: rgba(tokens.colorWorldDayTunnel), landmark: rgba(tokens.colorWorldDayLandmark),
  facades: tokens.colorWorldDayFacades.map((c) => rgba(c)),
  shadow: rgba(tokens.colorCarShadow),
  roofLight: tokens.lightDayRoofLight, sunX: tokens.lightDaySunX, sunY: tokens.lightDaySunY, ambient: tokens.lightDayAmbient,
  night: false,
};

export const nightPalette: Palette = {
  land: rgba(tokens.colorWorldNightLand), water: rgba(tokens.colorWorldNightWater), park: rgba(tokens.colorWorldNightPark),
  plaza: rgba(tokens.colorWorldNightPlaza), pedestrian: rgba(tokens.colorWorldNightPedestrian), rail: rgba(tokens.colorWorldNightRail), sidewalk: rgba(tokens.colorWorldNightSidewalk),
  asphalt: rgba(tokens.colorWorldNightAsphalt), alley: rgba(tokens.colorWorldNightAlley), marking: rgba(tokens.colorWorldNightMarking),
  centerLine: rgba(tokens.colorWorldNightCenterLine), bridgeDeck: rgba(tokens.colorWorldNightBridgeDeck),
  bridgeEdge: rgba(tokens.colorWorldNightBridgeEdge), tunnel: rgba(tokens.colorWorldNightTunnel), landmark: rgba(tokens.colorWorldNightLandmark),
  facades: tokens.colorWorldNightFacades.map((c) => rgba(c)),
  shadow: rgba(tokens.colorCarShadow),
  roofLight: tokens.lightNightRoofLight, sunX: tokens.lightNightSunX, sunY: tokens.lightNightSunY, ambient: tokens.lightNightAmbient,
  night: true,
};

const CITY_KEYS = [
  'land', 'water', 'park', 'plaza', 'pedestrian', 'rail', 'sidewalk', 'asphalt', 'alley', 'marking',
  'centerLine', 'bridgeDeck', 'bridgeEdge', 'tunnel', 'landmark', 'shadow',
] as const;

/** Token key prefix of a city skin: `nyc` → `colorCityNyc`, `new-york` → `colorCityNewYork`. */
export function cityTokenPrefix(cityId: string): string {
  return 'colorCity' + cityId.split(/[-_]/).filter((w) => w).map((w) => w[0]!.toUpperCase() + w.slice(1)).join('');
}

/** Optional style A keys (specs/style.md v2); a missing one means the thing is not drawn (or v1 roof). */
const OPTIONAL_CITY_KEYS = ['roof', 'roofEdge', 'castShadow'] as const;

const cityCache = new Map<string, Palette>();

/**
 * Day palette of a city skin (specs/style.md "Paleta"): `color.city.<id>` with the shared day
 * lights (`light.day`). A city without a complete skin in the tokens gets `color.world.day`.
 * Night stays `nightPalette` for every city.
 */
export function cityPalette(cityId: string): Palette {
  const hit = cityCache.get(cityId);
  if (hit) return hit;
  const tk = tokens as unknown as Record<string, unknown>;
  const pre = cityTokenPrefix(cityId);
  const key = (k: string): string => pre + k[0]!.toUpperCase() + k.slice(1);
  const facades = tk[key('facades')];
  let p = dayPalette;
  if (CITY_KEYS.every((k) => typeof tk[key(k)] === 'string') && Array.isArray(facades) && facades.length > 0) {
    const c = Object.fromEntries(CITY_KEYS.map((k) => [k, rgba(tk[key(k)] as string)])) as Record<(typeof CITY_KEYS)[number], Rgba>;
    p = { ...dayPalette, ...c, facades: (facades as string[]).map((h) => rgba(h)), night: false };
    for (const k of OPTIONAL_CITY_KEYS) {
      const v = tk[key(k)];
      if (typeof v === 'string') p[k] = rgba(v);
    }
  }
  cityCache.set(cityId, p);
  return p;
}

/** Inks of a city skin (`color.city.<id>.inks`, risograph), empty without them. */
export function cityInks(cityId: string): Rgba[] {
  const v = (tokens as unknown as Record<string, unknown>)[cityTokenPrefix(cityId) + 'Inks'];
  return Array.isArray(v) ? (v as string[]).map((h) => rgba(h)) : [];
}

export function groundColor(p: Palette, k: GroundKind): Rgba {
  switch (k) {
    case GroundKind.WATER: return p.water;
    case GroundKind.PARK: return p.park;
    case GroundKind.PLAZA: return p.plaza;
    case GroundKind.PEDESTRIAN: return p.pedestrian;
    case GroundKind.RAIL: return p.rail;
    default: return p.land;
  }
}
