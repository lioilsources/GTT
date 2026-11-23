import type { Contact } from 'planck';

import { CAT_BUILDINGS } from '../drive/car';
import type { DriveWorld } from '../drive/driveWorld';

/** Shortest gap between two `hit` actions of a world minigame (specs drift.md / sprint.md "Náraz"). */
export const HIT_GAP_MS = 500;

/**
 * Crashes of the player's car for world minigames (Drift, Sprint): a building wall (speed along the
 * contact normal), a bridge or tunnel rail (speed into the rail) or a traffic car (its impact
 * speed), each at least `minMps`. `take(atMs)` once per frame: true when a crash happened since the
 * last call and the previous reported one is at least HIT_GAP_MS ago.
 */
export class WorldHits {
  private pending = false;
  private lastMs = -Infinity;
  private readonly offs: Array<() => void> = [];

  constructor(private readonly drive: DriveWorld, private readonly minMps: number) {
    const onContact = (c: Contact): void => {
      const a = c.getFixtureA(), b = c.getFixtureB();
      const body = this.drive.car.body;
      const car = a.getBody() === body ? a : b.getBody() === body ? b : null;
      const other = car === a ? b : a;
      if (!car || other.getFilterCategoryBits() !== CAT_BUILDINGS) return;
      const n = c.getWorldManifold(null)?.normal;
      const v = body.getLinearVelocity();
      const into = n ? Math.abs(v.x * n.x + v.y * n.y) : Math.hypot(v.x, v.y);
      this.bump(into);
    };
    drive.world.on('begin-contact', onContact);
    this.offs.push(() => drive.world.off('begin-contact', onContact));
    drive.onRail = (out) => this.bump(out);
    this.offs.push(() => {
      if (drive.onRail) drive.onRail = null;
    });
    const off = drive.traffic?.onHit((_car, impact) => this.bump(impact));
    if (off) this.offs.push(off);
  }

  private bump(mps: number): void {
    if (mps >= this.minMps) this.pending = true;
  }

  /** Forgets crashes so far (session start). */
  reset(): void {
    this.pending = false;
    this.lastMs = -Infinity;
  }

  take(atMs: number): boolean {
    if (!this.pending) return false;
    this.pending = false;
    if (atMs - this.lastMs < HIT_GAP_MS) return false;
    this.lastMs = atMs;
    return true;
  }

  dispose(): void {
    for (const f of this.offs) f();
    this.offs.length = 0;
  }
}
