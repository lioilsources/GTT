import type { Tuning, TuningFlowTreeHit } from '../gen/tuning';
import { TREE_S, type NatureMap, type SurfaceName, type Tree } from '../world/nature';

/**
 * Driving on nature (specs/nature.md "Jízda", specs/flow.md "Strom jako měkká překážka", "Les"):
 * surface grip, the forest speed factor, soft trees and the water fall. Pure rules (no planck,
 * no Babylon); DriveWorld applies them. Literal numbers are fixed by the spec text.
 */

/** Physical trees: only within 80 m of the car, at most the 200 nearest (specs/flow.md). */
export const TREE_PHYS_M = 80;
export const TREE_PHYS_MAX = 200;
/** The candidate list is refreshed after the car moved this far (well inside TREE_PHYS_M). */
export const TREE_REFRESH_M = 10;
/** A fallen sapling comes back after 60 s, once out of view: farther than 150 m from the car. */
export const SAPLING_HIDE_S = 60;
export const SAPLING_BACK_M = 150;

export interface SurfaceEffect {
  /** × lateral grip of both axles and × brake deceleration. */
  grip: number;
  /** × cruise and top speed and engine force (forest only). */
  speed: number;
}

export function surfaceEffect(s: SurfaceName, t: Tuning): SurfaceEffect {
  const g = t.nature.grip;
  switch (s) {
    case 'grass': return { grip: g.grass, speed: 1 };
    case 'sand': return { grip: g.sand, speed: 1 };
    case 'dirt': return { grip: g.dirt, speed: 1 };
    case 'forest': return { grip: t.flow.forest.grip, speed: t.flow.forest.speedFactor };
    default: return { grip: g.asphalt, speed: 1 };
  }
}

export interface TreeHitResult {
  vx: number;
  vy: number;
  /** +1 trunk on the left (or dead ahead), −1 on the right; 0 for a sapling. */
  side: number;
  /** One-off heading change (rad), −side · yaw_kick_deg. */
  yaw: number;
  /** Unit direction the car is pushed in while overlapping (away from the trunk); 0, 0 for a sapling. */
  ax: number;
  ay: number;
  /** A sapling falls. */
  fell: boolean;
}

/**
 * The start of an overlap with a tree outside its cooldown (specs/flow.md): v = the car's velocity,
 * (cx, cy) its centre, (tx, ty) the trunk.
 */
export function treeHit(vx: number, vy: number, cx: number, cy: number, tx: number, ty: number, size: number, t: TuningFlowTreeHit): TreeHitResult {
  const sp = Math.hypot(vx, vy);
  if (size === TREE_S) {
    const k = t.saplingSpeedKeep;
    return { vx: vx * k, vy: vy * k, side: 0, yaw: 0, ax: 0, ay: 0, fell: true };
  }
  let k = t.speedKeep;
  if (sp > t.minSpeedMps && sp * k < t.minSpeedMps) k = t.minSpeedMps / sp;
  // v̂: the velocity direction, or nowhere when standing (then no side push direction either).
  const ux = sp > 1e-9 ? vx / sp : 0, uy = sp > 1e-9 ? vy / sp : 0;
  const cross = ux * (ty - cy) - uy * (tx - cx);
  const side = cross >= 0 ? 1 : -1;
  // Left normal of v̂ is (−uy, ux); away from the trunk = −side · normal.
  return {
    vx: vx * k, vy: vy * k, side, yaw: (-side * t.yawKickDeg * Math.PI) / 180,
    ax: side * uy, ay: -side * ux, fell: false,
  };
}

/** While overlapping: the velocity's component along a (away from the trunk) is at least push. */
export function treePush(vx: number, vy: number, ax: number, ay: number, push: number): { vx: number; vy: number } {
  const lat = vx * ax + vy * ay;
  if (lat >= push) return { vx, vy };
  return { vx: vx + (push - lat) * ax, vy: vy + (push - lat) * ay };
}

/** A tree hit for drawing (crown shake, leaves) and sound. */
export interface TreeEvent {
  key: string;
  x: number;
  y: number;
  size: number;
  /** Driving time of the hit. */
  t: number;
  /** Velocity direction at the hit (the sapling falls along it). */
  dirX: number;
  dirY: number;
}

interface Overlap {
  ax: number;
  ay: number;
  /** Pushed (a hit started this overlap) or only overlapping during the cooldown. */
  push: boolean;
}

/** Soft-tree state of the player's car (specs/flow.md "treeCd" and the overlaps). */
export class TreeContacts {
  readonly cd = new Map<string, number>();
  readonly overlap = new Map<string, Overlap>();
  /** Fallen saplings: key → driving time of the fall. */
  readonly fallen = new Map<string, number>();
  /** Hits since the start (scenarios count them). */
  hits = 0;
  readonly events: TreeEvent[] = [];
  /** Bumped when a sapling falls or comes back (the renderer hides fallen saplings). */
  fallenVersion = 0;
  private cand: Tree[] = [];
  private candX = Infinity;
  private candY = Infinity;
  private candVersion = -1;

  reset(): void {
    this.cd.clear();
    this.overlap.clear();
    this.cand = [];
    this.candX = this.candY = Infinity;
  }

  /** Physical trees: the 200 nearest within 80 m (ties by key), refreshed every 10 m. */
  candidates(nature: NatureMap, x: number, y: number): Tree[] {
    if (nature.version !== this.candVersion || Math.hypot(x - this.candX, y - this.candY) >= TREE_REFRESH_M) {
      this.candVersion = nature.version;
      this.candX = x;
      this.candY = y;
      const list = nature.treesNear(x, y, TREE_PHYS_M, []);
      if (list.length > TREE_PHYS_MAX) {
        const d = (t: Tree): number => (t.x - x) ** 2 + (t.y - y) ** 2;
        list.sort((a, b) => d(a) - d(b) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
        list.length = TREE_PHYS_MAX;
      }
      this.cand = list;
    }
    return this.cand;
  }

  /**
   * One step after the physics step. car = centre, velocity and half width; returns the new
   * velocity and the yaw kick to apply (or null when nothing changed). Not on the ground layer, in
   * the air or sinking: call clear() instead.
   */
  step(
    dt: number, time: number, nature: NatureMap, car: { x: number; y: number; vx: number; vy: number; halfWidth: number }, t: Tuning,
  ): { vx: number; vy: number; yaw: number } | null {
    for (const [k, v] of this.cd) {
      if (v - dt <= 0) this.cd.delete(k);
      else this.cd.set(k, v - dt);
    }
    for (const [k, ft] of this.fallen) {
      if (time - ft < SAPLING_HIDE_S) continue;
      const [x, y] = this.treePos(nature, k);
      if (x === null || Math.hypot(x - car.x, y! - car.y) > SAPLING_BACK_M) {
        this.fallen.delete(k);
        this.fallenVersion++;
      }
    }
    const th = t.flow.treeHit;
    const r = t.nature.trunkRadiusM + car.halfWidth;
    let vx = car.vx, vy = car.vy, yaw = 0, changed = false;
    const seen = new Set<string>();
    for (const tr of this.candidates(nature, car.x, car.y)) {
      if (this.fallen.has(tr.key)) continue;
      const dx = tr.x - car.x, dy = tr.y - car.y;
      if (dx * dx + dy * dy >= r * r) continue;
      seen.add(tr.key);
      let o = this.overlap.get(tr.key);
      if (!o) {
        o = { ax: 0, ay: 0, push: false };
        this.overlap.set(tr.key, o);
        if (!this.cd.has(tr.key)) {
          const h = treeHit(vx, vy, car.x, car.y, tr.x, tr.y, tr.size, th);
          const sp = Math.hypot(vx, vy);
          this.events.push({ key: tr.key, x: tr.x, y: tr.y, size: tr.size, t: time, dirX: sp > 1e-9 ? vx / sp : 1, dirY: sp > 1e-9 ? vy / sp : 0 });
          if (this.events.length > 32) this.events.shift();
          vx = h.vx;
          vy = h.vy;
          yaw += h.yaw;
          changed = true;
          this.hits++;
          this.cd.set(tr.key, th.cooldownS);
          if (h.fell) {
            this.fallen.set(tr.key, time);
            this.fallenVersion++;
          } else {
            o.ax = h.ax;
            o.ay = h.ay;
            o.push = true;
          }
        }
      }
      if (o.push) {
        const p = treePush(vx, vy, o.ax, o.ay, th.pushMps);
        if (p.vx !== vx || p.vy !== vy) {
          vx = p.vx;
          vy = p.vy;
          changed = true;
        }
      }
    }
    for (const k of this.overlap.keys()) if (!seen.has(k)) this.overlap.delete(k);
    return changed ? { vx, vy, yaw } : null;
  }

  /** No tree contact (other layer, air, water): overlaps end, cooldowns still run. */
  clear(dt: number): void {
    this.overlap.clear();
    for (const [k, v] of this.cd) {
      if (v - dt <= 0) this.cd.delete(k);
      else this.cd.set(k, v - dt);
    }
  }

  private treePos(nature: NatureMap, key: string): [number | null, number | null] {
    const slash = key.indexOf('/');
    const [cx, cy] = key.slice(0, slash).split('_').map(Number) as [number, number];
    const c = nature.chunks.get((cx + 32768) * 65536 + (cy + 32768));
    const tr = c?.trees[Number(key.slice(slash + 1))];
    return tr ? [tr.x, tr.y] : [null, null];
  }
}

/** Water fall (specs/nature.md "Voda"): the car sinks over water_fall.sink_s, then the tow. */
export class WaterFall {
  /** Seconds since the car entered the water, −1 = not sinking. */
  t = -1;
  private vx = 0;
  private vy = 0;
  /** Falls since the start (scenarios count them). */
  falls = 0;

  get sinking(): boolean {
    return this.t >= 0;
  }

  start(vx: number, vy: number): void {
    this.t = 0;
    this.vx = vx;
    this.vy = vy;
    this.falls++;
  }

  /** The velocity while sinking: the entry velocity falling linearly to 0 over sink_s, no control. */
  velocity(sinkS: number): { x: number; y: number } {
    const k = Math.max(0, 1 - this.t / Math.max(sinkS, 1e-6));
    return { x: this.vx * k, y: this.vy * k };
  }

  /** Advances; true when the car has sunk (then reset() after the respawn). */
  step(dt: number, sinkS: number): boolean {
    if (this.t < 0) return false;
    this.t += dt;
    return this.t >= sinkS - 1e-9;
  }

  /** 0 → 1 over the sink (drawing: scale 1 → 0.6, alpha → 0). */
  progress(sinkS: number): number {
    return this.t < 0 ? 0 : Math.min(1, this.t / Math.max(sinkS, 1e-6));
  }

  reset(): void {
    this.t = -1;
  }
}
