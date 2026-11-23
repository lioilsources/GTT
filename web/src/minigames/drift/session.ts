// Drift zone in the world (specs/minigames/drift.md "Svět"): sampling the car, the zone and the
// session clock over the pure rules. No DOM, no Babylon: the client feeds the car every frame.
import type { TuningMinigamesDrift } from '../../gen/tuning';
import { driftConfig, DriftRules, type DriftAction, type DriftResult, type DriftState } from './rules';

/** The car as the session needs it (m, m/s, rad). */
export interface DriftPose {
  x: number;
  y: number;
  heading: number;
  vx: number;
  vy: number;
  layer: number;
}

/** Below this speed β is 0 (spec "Vzorky"). */
export const SLIP_MIN_MPS = 0.5;

/** |β| in mrad: the angle between the car's heading and its velocity, floored. */
export function slipMrad(p: DriftPose): number {
  const sp = Math.hypot(p.vx, p.vy);
  if (sp < SLIP_MIN_MPS) return 0;
  const c = Math.cos(p.heading), s = Math.sin(p.heading);
  const f = p.vx * c + p.vy * s, l = -p.vx * s + p.vy * c;
  return Math.floor(Math.abs(Math.atan2(l, f)) * 1000);
}

export type DriftEvent = { kind: 'bank'; points: number } | { kind: 'over'; result: DriftResult };

/** One 90-second session around the zone centre (the spot's parking point, m). */
export class DriftSession {
  readonly rules = new DriftRules();
  state: DriftState;
  /** Session time, seconds. */
  clock = 0;
  private acc = 0;
  /** Every action applied, in order (debug, tests). */
  readonly log: DriftAction[] = [];
  /** Last sample's inZone (HUD "back into the ring"). */
  inZone = true;

  constructor(
    readonly t: TuningMinigamesDrift,
    level: number,
    readonly cx: number,
    readonly cy: number,
  ) {
    this.state = this.rules.init(driftConfig(t, level));
  }

  get over(): boolean {
    return this.state.phase === 'over';
  }
  get left(): number {
    return Math.max(0, this.t.sessionS - this.clock);
  }
  get ms(): number {
    return Math.floor(this.clock * 1000);
  }

  private act(a: DriftAction): void {
    this.state = this.rules.apply(this.state, a);
    this.log.push(a);
  }

  /** Ends the session now (timer, car switch, give-up); returns the result. */
  end(): DriftResult {
    if (!this.over) this.act({ by: 'timeout' });
    return this.rules.result(this.state)!;
  }

  /**
   * Once per frame with the world dt; `hit(atMs)` says whether the client reports a crash for this
   * frame at that session time (WorldHits.take).
   */
  update(dt: number, car: DriftPose, hit: (atMs: number) => boolean = () => false): DriftEvent[] {
    const ev: DriftEvent[] = [];
    if (this.over) return ev;
    this.clock += dt;
    if (this.clock >= this.t.sessionS) {
      const before = this.state.score;
      const result = this.end();
      if (result.score > before) ev.push({ kind: 'bank', points: result.score - before });
      ev.push({ kind: 'over', result });
      return ev;
    }
    if (hit(this.ms)) this.act({ by: 'player', op: 'hit', atMs: this.ms });
    const period = 1 / this.t.sampleHz;
    this.acc += dt;
    if (this.acc >= period) {
      this.acc %= period;
      const before = this.state.score;
      this.inZone = car.layer === 0 && Math.hypot(car.x - this.cx, car.y - this.cy) <= this.t.zoneM;
      this.act({
        by: 'player', op: 'sample', atMs: this.ms, slipMrad: slipMrad(car), speedCms: Math.floor(Math.hypot(car.vx, car.vy) * 100), inZone: this.inZone,
      });
      if (this.state.score > before) ev.push({ kind: 'bank', points: this.state.score - before });
    }
    return ev;
  }
}
