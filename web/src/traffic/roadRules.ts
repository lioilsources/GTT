import type { Tuning, TuningTraffic } from '../gen/tuning';
import { Prng } from '../rules/prng';
import type { RoadEdge, RoadGraph } from '../world/model';

/**
 * Deterministic parts of traffic (specs/traffic.md): traffic lights, lanes, the next-edge choice.
 * Pure (no DOM, no physics); port in packages/drive_core/lib/src/traffic/road_rules.dart, and the
 * unit tests of both clients check the same values.
 */

export const LIGHT_GREEN = 0;
export const LIGHT_AMBER = 1;
export const LIGHT_RED = 2;

/** Length of one full two-phase cycle in ms. */
export function cycleMs(t: TuningTraffic): number {
  return 2 * (t.greenMs + t.amberMs + t.allRedMs);
}

/** Per-node phase offset in [0, cycle): a deterministic function of the node id. */
export function signalOffset(node: number, seed: number, cycle: number): number {
  return new Prng((Math.imul(node, 2654435761 | 0) + seed) >>> 0).nextInt(cycle);
}

/** Light shown to approach group 0 or 1 at integer time tMs (ms). */
export function lightState(offset: number, group: number, tMs: number, t: TuningTraffic): number {
  const cycle = cycleMs(t);
  let p = (tMs + offset) % cycle;
  if (group === 1) p = (p + cycle / 2) % cycle;
  if (p < t.greenMs) return LIGHT_GREEN;
  if (p < t.greenMs + t.amberMs) return LIGHT_AMBER;
  return LIGHT_RED;
}

/** Signal clock: ms since start from the integer fixed-step counter. */
export function signalClockMs(step: number, stepHz: number): number {
  return Math.floor((step * 1000) / stepHz);
}

/** True when a car may leave `node` along edge `e` (one-way rule of specs/route.md). */
export function canLeave(e: RoadEdge, node: number): boolean {
  if (e.from === e.to) return false;
  if (e.oneway === 0) return e.from === node || e.to === node;
  return e.oneway > 0 ? e.from === node : e.to === node;
}

/** The layer of edge e at its end `node`. */
function layerAtNode(e: RoadEdge, node: number): number {
  return e.from === node ? e.layerFrom : e.layerTo;
}

/** Integer direction (dm) from `node` along e to its first point that differs from the node. */
function dirFromNode(g: RoadGraph, e: RoadEdge, node: number): [number, number] {
  const nx = Math.round(g.nodeXY[2 * node]! * 10), ny = Math.round(g.nodeXY[2 * node + 1]! * 10);
  const n = e.pointCount;
  for (let k = 1; k < n; k++) {
    const i = e.from === node ? k : n - 1 - k;
    const dx = Math.round(e.pts[2 * i]! * 10) - nx, dy = Math.round(e.pts[2 * i + 1]! * 10) - ny;
    if (dx !== 0 || dy !== 0) return [dx, dy];
  }
  return [1, 0];
}

/** Distinct, non-loop kept edges at a node in ascending index order. */
export function keptEdgesAt(g: RoadGraph, node: number): number[] {
  const out: number[] = [];
  for (const ei of g.nodeEdges[node]!) {
    const e = g.edges[ei]!;
    if (!e.kept || e.from === e.to || out.includes(ei)) continue;
    out.push(ei);
  }
  return out.sort((a, b) => a - b);
}

/** One way into a signalled node. */
export interface Approach {
  signal: number;
  edge: number;
  /** Node the approach leads into. */
  node: number;
  group: number;
  /** Distance of the stop line from the node (m). */
  stopM: number;
  /** Indicator position (m). */
  x: number;
  y: number;
}

export interface Signals {
  nodes: number[];
  offsets: number[];
  approaches: Approach[];
  /** Per edge: approach index when driving from → to (into `to`), else −1. */
  approachTo: Int32Array;
  /** Per edge: approach index when driving to → from (into `from`), else −1. */
  approachFrom: Int32Array;
  /**
   * Distance from the end of the edge to the signal node (m): 0 on the approach edge itself, more
   * on the edges of an unbranched chain leading to it (the citypack splits roads at every node).
   */
  extraTo: Float32Array;
  extraFrom: Float32Array;
}

/** Carriageway half width (m): the same as the road markings (render/geometry.ts). */
export function carriageHalf(e: RoadEdge, tuning: Tuning): number {
  return Math.max(e.width - 2 * tuning.sidewalkWidthM, tuning.laneWidthM) / 2;
}

/** Finds the signalled nodes and their approaches (specs/traffic.md "Semafory"). */
export function buildSignals(g: RoadGraph, tuning: Tuning, leftHand: boolean): Signals {
  const t = tuning.traffic;
  const cycle = cycleMs(t);
  const nodes: number[] = [], offsets: number[] = [], approaches: Approach[] = [];
  const approachTo = new Int32Array(g.edges.length).fill(-1);
  const approachFrom = new Int32Array(g.edges.length).fill(-1);
  const extraTo = new Float32Array(g.edges.length);
  const extraFrom = new Float32Array(g.edges.length);
  const side = leftHand ? -1 : 1;
  for (let n = 0; n < g.nodeEdges.length; n++) {
    const kept = keptEdgesAt(g, n);
    if (kept.length < t.signalMinEdges) continue;
    let main = 0, ground = true;
    for (const ei of kept) {
      const e = g.edges[ei]!;
      if (t.signalClasses.includes(e.roadClass)) main++;
      if (layerAtNode(e, n) !== 0) ground = false;
    }
    if (main < t.signalMinMain || !ground) continue;
    const signal = nodes.length;
    nodes.push(n);
    offsets.push(signalOffset(n, t.signalSeed, cycle));
    const [rx, ry] = dirFromNode(g, g.edges[kept[0]!]!, n);
    const nx = g.nodeXY[2 * n]!, ny = g.nodeXY[2 * n + 1]!;
    for (const ei of kept) {
      const e = g.edges[ei]!;
      // An approach is an edge a car may drive along into n: it may leave its other end.
      const other = e.from === n ? e.to : e.from;
      if (!canLeave(e, other)) continue;
      const [vx, vy] = dirFromNode(g, e, n);
      const group = Math.abs(rx * vy - ry * vx) < Math.abs(rx * vx + ry * vy) ? 0 : 1;
      let stop = 0;
      for (const oi of kept) if (oi !== ei) stop = Math.max(stop, g.edges[oi]!.width / 2);
      stop += t.stopMarginM;
      // Indicator: on the approach at the stop line, on the driver's side of the carriageway.
      const l = Math.hypot(vx, vy);
      const ux = vx / l, uy = vy / l; // from node outwards; travel direction is −u
      const off = (carriageHalf(e, tuning) + t.lightSideM) * side;
      // Right of the travel direction (−ux, −uy) is (−uy, ux).
      approaches.push({ signal, edge: ei, node: n, group, stopM: stop, x: nx + ux * stop - uy * off, y: ny + uy * stop + ux * off });
      if (e.to === n) approachTo[ei] = approaches.length - 1;
      else approachFrom[ei] = approaches.length - 1;
    }
  }
  // Upstream chains: through nodes with exactly two kept edges the way on is unique, so a car
  // there already sees the light ahead (specs/traffic.md "Řetězy").
  const isSignal = new Uint8Array(g.nodeEdges.length);
  for (const n of nodes) isSignal[n] = 1;
  approaches.forEach((ap, a) => {
    let cur = g.edges[ap.edge]!;
    let node = cur.from === ap.node ? cur.to : cur.from;
    let extra = cur.length;
    while (extra - ap.stopM < t.lookAheadM && !isSignal[node] && !g.border[node]) {
      const kept = keptEdgesAt(g, node);
      if (kept.length !== 2) break;
      const f = g.edges[kept[0] === cur.index ? kept[1]! : kept[0]!]!;
      const other = f.from === node ? f.to : f.from;
      if (!canLeave(f, other)) break;
      if (f.to === node) {
        if (approachTo[f.index]! >= 0) break;
        approachTo[f.index] = a;
        extraTo[f.index] = extra;
      } else {
        if (approachFrom[f.index]! >= 0) break;
        approachFrom[f.index] = a;
        extraFrom[f.index] = extra;
      }
      extra += f.length;
      cur = f;
      node = other;
    }
  });
  return { nodes, offsets, approaches, approachTo, approachFrom, extraTo, extraFrom };
}

/** Lanes per travel direction (specs/traffic.md "Pruhy"). */
export function lanesPerDir(e: RoadEdge, tuning: Tuning): number {
  const c = carriageHalf(e, tuning);
  const l = Math.max(1, Math.round((2 * c) / tuning.laneWidthM));
  return e.oneway === 0 ? Math.max(1, Math.floor(l / 2)) : l;
}

/** Lateral offset of lane i from the centre line, + = right of the travel direction. */
export function laneOffset(e: RoadEdge, lane: number, tuning: Tuning, leftHand: boolean): number {
  const c = carriageHalf(e, tuning);
  const l = Math.max(1, Math.round((2 * c) / tuning.laneWidthM));
  const off = e.oneway === 0 ? ((lane + 0.5) * c) / Math.max(1, Math.floor(l / 2)) : c - ((lane + 0.5) * 2 * c) / l;
  return leftHand ? -off : off;
}

/**
 * The next edge after arriving at `node` along `from` (specs/traffic.md "Volba další hrany"):
 * an edge index, or −1 when the car has to disappear.
 */
export function chooseNext(g: RoadGraph, node: number, from: number, rng: Prng, scratch: number[] = []): number {
  if (g.border[node]) return -1;
  scratch.length = 0;
  const list = g.nodeEdges[node]!;
  // nodeEdges is in ascending index order (built edge by edge); skip duplicates of loops.
  for (let k = 0; k < list.length; k++) {
    const ei = list[k]!;
    if (ei === from || (k > 0 && list[k - 1] === ei)) continue;
    const e = g.edges[ei]!;
    if (e.kept && canLeave(e, node)) scratch.push(ei);
  }
  if (scratch.length === 0) return canLeave(g.edges[from]!, node) ? from : -1;
  return scratch[rng.nextInt(scratch.length)]!;
}

/**
 * Pursuit: the edge at `node` that heads most towards the goal (gx, gy) (specs/police.md
 * "chooseToward"). Any kept edge counts in either direction (sirens), including `from` (U-turn);
 * ties keep the lowest index. −1 at a border node or when there is no edge at all.
 */
export function chooseToward(g: RoadGraph, node: number, from: number, gx: number, gy: number): number {
  if (g.border[node]) return -1;
  const nx = g.nodeXY[2 * node]!, ny = g.nodeXY[2 * node + 1]!;
  const tl = Math.hypot(gx - nx, gy - ny);
  const tx = tl > 0 ? (gx - nx) / tl : 0, ty = tl > 0 ? (gy - ny) / tl : 0;
  let best = -1, bestDot = -Infinity;
  for (const ei of keptEdgesAt(g, node)) {
    const [dx, dy] = dirFromNode(g, g.edges[ei]!, node);
    const l = Math.hypot(dx, dy);
    const d = l > 0 ? (dx * tx + dy * ty) / l : -1;
    if (d > bestDot) {
      bestDot = d;
      best = ei;
    }
  }
  return best < 0 && g.edges[from]?.kept ? from : best;
}

/**
 * Sideways shift of a traffic car's lane point round parked cars (specs/traffic.md step 8).
 * `obs` holds `n` quads (lx, ly, ext, phl): position ahead / to the right of the lane point,
 * lateral half extent and half length of each parked car. Negative = to the left.
 */
export function swerveShift(
  obs: ArrayLike<number>, n: number, hl: number, hw: number,
  t: { swerveAheadM: number; swerveMarginM: number; swerveMaxM: number },
): number {
  let shift = 0;
  for (let i = 0; i < n; i++) {
    const lx = obs[4 * i]!, ly = obs[4 * i + 1]!, ext = obs[4 * i + 2]!, phl = obs[4 * i + 3]!;
    if (lx < -(hl + phl) || lx > t.swerveAheadM + hl + phl) continue;
    const need = hw + ext + t.swerveMarginM;
    if (Math.abs(ly) >= need) continue;
    const s = ly >= 0 ? ly - need : ly + need;
    if (Math.abs(s) > Math.abs(shift)) shift = s;
  }
  return Math.abs(shift) > t.swerveMaxM ? 0 : shift;
}
