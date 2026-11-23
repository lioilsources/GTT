import type { Spots } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';
import type { TuningPhone } from '../gen/tuning';
import type { RoadGraph } from '../world/model';
import type { MapNatureSource } from './mapNature';

/** The Map app (specs/phone.md "Mapa"): north-up overview of kept roads, spots, player and route. */
export interface MapViewEnv {
  graph: RoadGraph;
  spots: Spots;
  /** City area ring, metres (interleaved). */
  area: Float32Array;
  phone: TuningPhone;
  player: () => { x: number; y: number; heading: number };
  route: () => number[];
  target: () => string | null;
  /** Extra points (metres, colour) drawn over the spots, e.g. a ringing booth (specs/booths.md). */
  extra?: () => Array<{ x: number; y: number; color: string }>;
  /** Water, parks and their names (specs/nature.md "mapa v telefonu"); absent without nature. */
  nature?: MapNatureSource | null;
}

/** Label sizes on the map by area (presentation): big bodies get the bigger font. */
const LABEL_PX = [[1_000_000, 12], [100_000, 11], [0, 10]] as const;

/** Fits the bounds of a ring into w × h with padding; north up. */
export function mapFit(ring: ArrayLike<number>, w: number, h: number, pad: number): { s: number; ox: number; oy: number } {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (let i = 0; i + 1 < ring.length; i += 2) {
    x0 = Math.min(x0, ring[i]!);
    x1 = Math.max(x1, ring[i]!);
    y0 = Math.min(y0, ring[i + 1]!);
    y1 = Math.max(y1, ring[i + 1]!);
  }
  if (!Number.isFinite(x0)) return { s: 1, ox: w / 2, oy: h / 2 };
  const s = Math.min((w - 2 * pad) / Math.max(1, x1 - x0), (h - 2 * pad) / Math.max(1, y1 - y0));
  // screen = (x * s + ox, -y * s + oy), centred.
  return { s, ox: w / 2 - ((x0 + x1) / 2) * s, oy: h / 2 + ((y0 + y1) / 2) * s };
}

export function mountMap(host: HTMLElement, env: MapViewEnv): () => void {
  const canvas = document.createElement('canvas');
  canvas.className = 'phone-map';
  host.append(canvas);
  const ctx = canvas.getContext('2d')!;
  let roads: Path2D | null = null;
  let fit = { s: 1, ox: 0, oy: 0 };
  let w = 0, hgt = 0;
  // The nature fill layer is drawn once per layout and data version into its own canvas.
  const fill = document.createElement('canvas');
  let fillVersion = -1;
  env.nature?.start();

  const layout = (): void => {
    const r = canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    if (r.width === w && r.height === hgt) return;
    fillVersion = -1;
    w = r.width;
    hgt = r.height;
    canvas.width = Math.max(1, Math.round(w * dpr));
    canvas.height = Math.max(1, Math.round(hgt * dpr));
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    fit = mapFit(env.area, w, hgt, env.phone.mapPaddingPx);
    roads = new Path2D();
    for (const e of env.graph.edges) {
      if (!e.kept) continue;
      for (let i = 0; i < e.pointCount; i++) {
        const x = e.pts[2 * i]! * fit.s + fit.ox, y = -e.pts[2 * i + 1]! * fit.s + fit.oy;
        if (i === 0) roads.moveTo(x, y);
        else roads.lineTo(x, y);
      }
    }
  };

  const sx = (x: number): number => x * fit.s + fit.ox;
  const sy = (y: number): number => -y * fit.s + fit.oy;

  const natureFill = (): void => {
    const n = env.nature?.data;
    if (!n || n.version === fillVersion) return;
    fillVersion = n.version;
    fill.width = canvas.width;
    fill.height = canvas.height;
    const f = fill.getContext('2d')!;
    f.setTransform(canvas.width / Math.max(w, 1), 0, 0, canvas.height / Math.max(hgt, 1), 0, 0);
    const masses = (list: typeof n.wood, col: string): void => {
      f.fillStyle = col;
      const p = new Path2D();
      for (const m of list) {
        let start = 0;
        for (const end of m.ends) {
          for (let i = start; i < end; i++) {
            const x = sx(m.xy[2 * i]!), y = sy(m.xy[2 * i + 1]!);
            if (i === start) p.moveTo(x, y);
            else p.lineTo(x, y);
          }
          p.closePath();
          start = end;
        }
      }
      f.fill(p, 'evenodd');
    };
    masses(n.park, tokens.colorGreenParkland);
    masses(n.wood, tokens.colorGreenWood);
    f.fillStyle = f.strokeStyle = tokens.colorWaterRiver;
    f.lineWidth = 0.6;
    const p = new Path2D();
    for (const t of n.water) {
      for (let i = 0; i + 5 < t.length; i += 6) {
        p.moveTo(sx(t[i]!), sy(t[i + 1]!));
        p.lineTo(sx(t[i + 2]!), sy(t[i + 3]!));
        p.lineTo(sx(t[i + 4]!), sy(t[i + 5]!));
        p.closePath();
      }
    }
    f.fill(p);
    // A thin stroke closes the hairline gaps between triangles.
    f.stroke(p);
  };

  /** Names by area, biggest first; a name that would overlap one already drawn is skipped. */
  const natureLabels = (): void => {
    const n = env.nature?.data;
    if (!n || n.labels.length === 0) return;
    const boxes: Array<[number, number, number, number]> = [];
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (const l of n.labels) {
      const x = sx(l.x), y = sy(l.y);
      if (x < 0 || y < 0 || x > w || y > hgt) continue;
      const px = LABEL_PX.find(([a]) => l.area >= a)![1];
      ctx.font = `${l.water ? 'italic ' : ''}600 ${px}px system-ui, sans-serif`;
      const tw = ctx.measureText(l.name).width / 2 + 2, th = px / 2 + 1;
      if (x - tw < 0 || x + tw > w) continue;
      if (boxes.some(([x0, y0, x1, y1]) => x + tw > x0 && x - tw < x1 && y + th > y0 && y - th < y1)) continue;
      boxes.push([x - tw, y - th, x + tw, y + th]);
      ctx.fillStyle = l.water ? tokens.colorWaterLine : tokens.colorGreenWood;
      ctx.fillText(l.name, x, y);
    }
  };

  const draw = (): void => {
    layout();
    ctx.fillStyle = tokens.colorPhoneMapLand;
    ctx.fillRect(0, 0, w, hgt);
    if (env.nature) {
      natureFill();
      ctx.save();
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.drawImage(fill, 0, 0);
      ctx.restore();
    }
    ctx.strokeStyle = tokens.colorPhoneMapRoad;
    ctx.lineWidth = 1;
    if (roads) ctx.stroke(roads);
    const route = env.route();
    if (route.length >= 4) {
      ctx.strokeStyle = tokens.colorUiRouteArrow;
      ctx.lineWidth = env.phone.mapRoutePx;
      ctx.lineJoin = ctx.lineCap = 'round';
      ctx.beginPath();
      for (let i = 0; i + 1 < route.length; i += 2) {
        if (i === 0) ctx.moveTo(sx(route[i]!), sy(route[i + 1]!));
        else ctx.lineTo(sx(route[i]!), sy(route[i + 1]!));
      }
      ctx.stroke();
    }
    natureLabels();
    const target = env.target();
    for (const s of env.spots.items) {
      // Only a ringing booth shows, as an extra point; photo spots are extra points in their colour.
      if (s.kind === 'booth' || s.kind === 'photo') continue;
      const r = env.phone.mapSpotPx * (s.id === target ? 1.6 : 1);
      ctx.fillStyle = s.minigame ? tokens.colorPhoneMapGame : tokens.colorPhoneMapSpot;
      ctx.beginPath();
      ctx.arc(sx(s.x / 10), sy(s.y / 10), s.minigame ? r : r * 0.7, 0, 2 * Math.PI);
      ctx.fill();
    }
    for (const e of env.extra?.() ?? []) {
      ctx.fillStyle = e.color;
      ctx.beginPath();
      ctx.arc(sx(e.x), sy(e.y), env.phone.mapSpotPx * 1.6, 0, 2 * Math.PI);
      ctx.fill();
    }
    const p = env.player(), pr = env.phone.mapPlayerPx;
    ctx.save();
    ctx.translate(sx(p.x), sy(p.y));
    ctx.rotate(-p.heading);
    ctx.fillStyle = tokens.colorPhoneMapPlayer;
    ctx.beginPath();
    ctx.moveTo(pr * 1.4, 0);
    ctx.lineTo(-pr, pr);
    ctx.lineTo(-pr * 0.4, 0);
    ctx.lineTo(-pr, -pr);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  };

  let raf = 0;
  let lastDraw = 0;
  const loop = (now: number): void => {
    if (now - lastDraw > 100) {
      lastDraw = now;
      draw();
    }
    raf = requestAnimationFrame(loop);
  };
  raf = requestAnimationFrame(loop);
  return () => {
    cancelAnimationFrame(raf);
    canvas.remove();
  };
}
