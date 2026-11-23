import type { ShellApi } from './shell';

/**
 * Game clock for timing games (stickball, doubledutch): milliseconds of unpaused time since start.
 * `frame(now)` once per animation frame; `at(now)` reads the clock at an input event's time, so a
 * tap between two frames gets its own time instead of the frame's.
 */
export class GameClock {
  private ms = 0;
  private last = -1;

  constructor(private readonly paused: () => boolean) {}

  static of(api: ShellApi): GameClock {
    return new GameClock(() => api.paused);
  }

  frame(now: number): number {
    if (this.paused()) this.last = -1;
    else {
      if (this.last >= 0) this.ms += Math.max(0, now - this.last);
      this.last = now;
    }
    return this.ms;
  }

  at(now: number): number {
    return this.last >= 0 && !this.paused() ? this.ms + Math.max(0, now - this.last) : this.ms;
  }

  get now(): number {
    return this.ms;
  }
}
