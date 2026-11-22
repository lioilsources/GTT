import type { Spots } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';
import type { TuningPhone } from '../gen/tuning';
import type { RoadGraph } from '../world/model';

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
}

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

  const layout = (): void => {
    const r = canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    if (r.width === w && r.height === hgt) return;
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

  const draw = (): void => {
    layout();
    ctx.fillStyle = tokens.colorPhoneMapLand;
    ctx.fillRect(0, 0, w, hgt);
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
    const target = env.target();
    for (const s of env.spots.items) {
      if (s.kind === 'booth') continue; // only a ringing booth shows, as an extra point
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
