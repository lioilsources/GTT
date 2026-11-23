import type { RulesResult } from './rules';
import type { ShellApi } from './shell';

/**
 * Turn driver for the board minigames against an NPC: the opponent answers after `thinkS`,
 * waits while paused, and the game ends on the rules result after a short pause.
 */
export function turnDriver(opts: {
  api: ShellApi;
  thinkS: number;
  /** True when the opponent is to move. */
  aiTurn(): boolean;
  /** Plays one opponent move (rules.apply, redraw, then `after()`). */
  aiMove(): void;
  result(): RulesResult | null;
}): { after(): boolean; stop(): void } {
  let timer = 0;
  let ended = false;
  const schedule = (): void => {
    window.clearTimeout(timer);
    if (ended || !opts.aiTurn()) return;
    timer = window.setTimeout(function tick() {
      if (opts.api.paused) {
        timer = window.setTimeout(tick, 200);
        return;
      }
      if (ended) return;
      opts.aiMove();
    }, opts.thinkS * 1000);
  };
  /** Call after every applied move; returns true when the game ended. */
  const after = (): boolean => {
    const r = opts.result();
    if (r) {
      ended = true;
      window.clearTimeout(timer);
      timer = window.setTimeout(() => opts.api.finish(r), 900);
      return true;
    }
    schedule();
    return false;
  };
  return { after, stop: () => { ended = true; window.clearTimeout(timer); } };
}
