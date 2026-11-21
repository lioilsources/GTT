import type { Tuning } from '../gen/tuning';
import type { ControlInput } from './controls';
import type { DriveWorld } from './driveWorld';
import type { RoutePath } from './route';

/** Drives a route without a player (specs/bench.md). Pure logic, runs every fixed physics step. */
export class Autopilot {
  s = 0;
  respawns = 0;
  finished = false;
  private slowFor = 0;

  constructor(
    readonly route: RoutePath,
    readonly tuning: Tuning,
  ) {}

  /** Puts the car at the route start, facing along it. */
  start(drive: DriveWorld): void {
    const p = this.route.at(0);
    drive.spawn(p.x, p.y, p.dir);
    this.s = 0;
  }

  step(drive: DriveWorld, input: ControlInput, dt: number): void {
    const b = this.tuning.bench;
    const car = drive.car;
    const r = this.route;
    this.s = r.project(car.x, car.y, this.s - b.searchBackM, this.s + b.searchAheadM);
    if (this.s >= r.length - b.arriveM) {
      this.finished = true;
      input.reset();
      input.brake = 1;
      return;
    }
    const v = car.speed;
    const target = r.at(this.s + b.lookaheadM + b.lookaheadPerMps * v);
    let e = Math.atan2(target.y - car.y, target.x - car.x) - car.heading;
    while (e > Math.PI) e -= 2 * Math.PI;
    while (e < -Math.PI) e += 2 * Math.PI;
    input.reset();
    input.steer = Math.min(1, Math.max(-1, -b.steerGain * e));
    const want = r.maxTurn(this.s, this.s + b.cornerLookaheadM) > b.cornerTurnRad ? b.cornerSpeedMps : this.tuning.speedMps.cruise;
    input.brake = Math.min(1, Math.max(0, (v - want) * b.brakePerMps));

    this.slowFor = v < b.stuckMps ? this.slowFor + dt : 0;
    if (this.slowFor >= b.stuckS) {
      const p = r.at(this.s + b.respawnAheadM);
      drive.spawn(p.x, p.y, p.dir);
      this.s += b.respawnAheadM;
      this.slowFor = 0;
      this.respawns++;
    }
  }
}

/** Frame statistics of specs/bench.md (frame times in ms). */
export function frameStats(ms: number[]): { fpsAvg: number; p50: number; p99: number; fps1Low: number } {
  if (ms.length === 0) return { fpsAvg: 0, p50: 0, p99: 0, fps1Low: 0 };
  const sorted = [...ms].sort((a, b) => a - b);
  const total = ms.reduce((a, b) => a + b, 0);
  const pick = (q: number): number => sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))]!;
  const p99 = pick(0.99);
  return { fpsAvg: (ms.length * 1000) / total, p50: pick(0.5), p99, fps1Low: 1000 / p99 };
}
