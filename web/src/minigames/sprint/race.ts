// Sprint A→B in the world (specs/minigames/sprint.md "Svět"): destination, route, checkpoints,
// countdown and the race clock over the pure rules. No DOM, no Babylon: the client feeds the car.
import { findRoute, type Route, type RouteGraph } from '../../drive/gps';
import type { TuningMinigamesSprint } from '../../gen/tuning';
import { navGoal, navStart, type NavTarget } from '../../phone/nav';
import type { EdgeHit, RoadGraph } from '../../world/model';
import type { TaxiDest } from '../taxi/shift';
import { sprintConfig, SprintRules, type SprintAction, type SprintResult, type SprintState } from './rules';

/** What the race needs from the city. */
export interface SprintWorld {
  graph: RoadGraph;
  route: RouteGraph;
  lensDm: Int32Array;
  /** nav.search_m: start edge search radius. */
  searchM: number;
}

export interface SprintPose {
  x: number;
  y: number;
  heading: number;
  layer: number;
}

/** A checkpoint (or the finish): point (m), half the corridor width, distance along the route (dm). */
export interface SprintGate {
  x: number;
  y: number;
  /** Direction of the road there (unit vector), for drawing the gate across it. */
  dirX: number;
  dirY: number;
  halfWidth: number;
  atDm: number;
  /** Where the navigation leads for this gate. */
  target: NavTarget;
}

export interface SprintPlan {
  dest: TaxiDest;
  route: Route;
  distDm: number;
  gates: SprintGate[];
  finish: SprintGate;
}

/** Route from the start to the destination by specs/route.md; null when no road route exists. */
export function sprintRoute(w: SprintWorld, start: { hit: EdgeHit | null; x: number; y: number; heading: number }, dest: TaxiDest): Route | null {
  const s = navStart(w.graph, start.hit, start.x, start.y, start.heading, w.searchM);
  if (!s) return null;
  const r = findRoute(w.route, s.node, navGoal(w.graph, dest).node);
  return r.cost >= 0 ? r : null;
}

/**
 * Checkpoints along the route (spec "Trasa a kontroly"): checkpoint k (from 1) at the first route
 * node where the travelled length ≥ k × cp_every_m while more than cp_every_m / 2 is left to the
 * goal; one checkpoint per node.
 */
export function sprintPlan(w: SprintWorld, t: TuningMinigamesSprint, dest: TaxiDest, route: Route): SprintPlan {
  const g = w.graph;
  const everyDm = Math.round(t.cpEveryM * 10);
  const cum = [0];
  for (const e of route.edges) cum.push(cum[cum.length - 1]! + w.lensDm[e]!);
  const distDm = cum[cum.length - 1]!;
  const gates: SprintGate[] = [];
  let k = 1;
  for (let i = 1; i < route.nodes.length; i++) {
    if (cum[i]! < k * everyDm || (distDm - cum[i]!) * 2 <= everyDm) continue;
    const node = route.nodes[i]!, ei = route.edges[i - 1]!, e = g.edges[ei]!;
    const x = g.nodeXY[2 * node]!, y = g.nodeXY[2 * node + 1]!;
    // Direction of travel into the node along the edge's last (or first) segment.
    const pts = e.pts, n = e.pointCount;
    const [ax, ay] = e.to === node ? [pts[2 * (n - 2)]!, pts[2 * (n - 2) + 1]!] : [pts[2]!, pts[3]!];
    const len = Math.hypot(x - ax, y - ay) || 1;
    gates.push({
      x, y, dirX: (x - ax) / len, dirY: (y - ay) / len, halfWidth: e.width / 2, atDm: cum[i]!,
      target: { id: `sprint:cp${k}`, name: '', edge: ei, parkX: Math.round(x * 10), parkY: Math.round(y * 10) },
    });
    k++;
  }
  const de = g.edges[dest.edge]!;
  const fp = de.pts;
  const fdx = fp[fp.length - 2]! - fp[0]!, fdy = fp[fp.length - 1]! - fp[1]!;
  const fl = Math.hypot(fdx, fdy) || 1;
  const finish: SprintGate = {
    x: dest.parkX / 10, y: dest.parkY / 10, dirX: fdx / fl, dirY: fdy / fl, halfWidth: de.width / 2, atDm: distDm, target: dest,
  };
  return { dest, route, distDm, gates, finish };
}

export type SprintEvent =
  | { kind: 'picked'; dest: TaxiDest }
  | { kind: 'go' }
  | { kind: 'cp'; index: number; splitMs: number; parAtMs: number }
  | { kind: 'over'; result: SprintResult };

/** One race. `update` once per frame with the world dt (scaled like driving). */
export class SprintRace {
  readonly rules = new SprintRules();
  state: SprintState;
  /** Time since the start of the minigame, seconds. */
  clock = 0;
  plan: SprintPlan | null = null;
  /** Every action applied, in order (debug, tests). */
  readonly log: SprintAction[] = [];
  private readonly byId: Map<string, TaxiDest>;

  constructor(
    readonly world: SprintWorld,
    readonly t: TuningMinigamesSprint,
    readonly dests: readonly TaxiDest[],
    level: number,
    seed: number,
  ) {
    this.byId = new Map(dests.map((d) => [d.id, d]));
    this.state = this.rules.init(sprintConfig(t, dests.map((d) => d.id), level), seed);
  }

  get over(): boolean {
    return this.state.phase === 'over';
  }
  get ms(): number {
    return Math.floor(this.clock * 1000);
  }
  /** Countdown left (s) while ready. */
  get countdown(): number {
    return this.state.phase === 'ready' ? Math.max(0, this.t.countdownS - this.clock) : 0;
  }
  /** Race time (s) since go. */
  get raceS(): number {
    return this.state.phase === 'run' ? this.clock - this.state.goMs / 1000 : this.state.timeMs / 1000;
  }
  /** The gate the car must pass next (a checkpoint, then the finish). */
  get next(): SprintGate | null {
    const p = this.plan;
    if (!p || this.state.phase !== 'run') return p && this.state.phase === 'ready' ? p.gates[0] ?? p.finish : null;
    return p.gates[this.state.passed] ?? p.finish;
  }

  private act(a: SprintAction): void {
    this.state = this.rules.apply(this.state, a);
    this.log.push(a);
  }

  /** Ends the race now (time cap, give-up, car switch); returns the result. */
  end(): SprintResult {
    if (!this.over) this.act({ by: 'timeout' });
    return this.rules.result(this.state)!;
  }

  /**
   * pick (spec "Start"): `allow` = destinations dest_min_m … dest_max_m from the start with a road
   * route; none = all. A picked destination without a route ends the race (timeout).
   */
  begin(start: { hit: EdgeHit | null; x: number; y: number; heading: number }): SprintEvent[] {
    const routes = new Map<string, Route>();
    const allow: string[] = [];
    for (const d of this.dests) {
      const s = Math.hypot(d.parkX / 10 - start.x, d.parkY / 10 - start.y);
      if (s < this.t.destMinM || s > this.t.destMaxM) continue;
      const r = sprintRoute(this.world, start, d);
      if (r) {
        routes.set(d.id, r);
        allow.push(d.id);
      }
    }
    this.act({ by: 'player', op: 'pick', allow });
    if (this.over) return [{ kind: 'over', result: this.rules.result(this.state)! }];
    const dest = this.byId.get(this.state.dest)!;
    const route = routes.get(dest.id) ?? sprintRoute(this.world, start, dest);
    if (!route) return [{ kind: 'over', result: this.end() }];
    this.plan = sprintPlan(this.world, this.t, dest, route);
    return [{ kind: 'picked', dest }];
  }

  update(dt: number, car: SprintPose, hit: (atMs: number) => boolean = () => false): SprintEvent[] {
    const ev: SprintEvent[] = [];
    const p = this.plan;
    if (this.over || !p) return ev;
    this.clock += dt;
    const st = this.state;
    if (st.phase === 'ready') {
      if (this.clock >= this.t.countdownS) {
        this.act({ by: 'player', op: 'go', atMs: this.ms, distDm: p.distDm, cps: p.gates.length });
        ev.push({ kind: 'go' });
      }
      return ev;
    }
    if (this.clock - st.goMs / 1000 >= this.t.timeCapS) {
      ev.push({ kind: 'over', result: this.end() });
      return ev;
    }
    if (hit(this.ms)) this.act({ by: 'player', op: 'hit', atMs: this.ms });
    const g = this.next!;
    const reach = this.t.cpRadiusM + g.halfWidth;
    if (car.layer === 0 && Math.hypot(car.x - g.x, car.y - g.y) <= reach) {
      if (this.state.passed < this.state.cps) {
        const index = this.state.passed;
        this.act({ by: 'player', op: 'cp', atMs: this.ms, index });
        const splitMs = this.state.splits[index]!;
        ev.push({ kind: 'cp', index, splitMs, parAtMs: p.distDm > 0 ? Math.floor((this.state.parMs * g.atDm) / p.distDm) : 0 });
      } else {
        this.act({ by: 'player', op: 'finish', atMs: this.ms });
        ev.push({ kind: 'over', result: this.rules.result(this.state)! });
      }
    }
    return ev;
  }
}
