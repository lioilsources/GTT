import { Prng } from '../../rules/prng';
import type { TuningMinigamesKulecnik } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';
import { clamp, isqrt, normalizedAim, off, rect, shotVelocity, simulate, trunc, type Body, type World } from '../physics';

/** specs/minigames/kulecnik.md, version 1 (physics: specs/minigames/fyzika.md v1). */
export interface KulecnikConfig {
  tableW: number;
  tableH: number;
  ballR: number;
  pockets: number[];
  rackDx: number;
  rackDy: number;
  rack: number[];
  maxSpeed: number;
  dec: number;
  eBall: number;
  eCushion: number;
  maxSteps: number;
  aiCandidates: number[];
  aiScatter: number[];
  aiPowerBase: number;
  aiPowerPerM: number;
  starLeft: number[];
}

export type Side = 'player' | 'ai';
export type Group = '' | 'solid' | 'stripe';

export interface Ball {
  x: number;
  y: number;
  on: boolean;
}

export interface LastShot {
  by: '' | Side;
  firstHit: number;
  pots: number[];
  foul: boolean;
}

export interface KulecnikState {
  balls: Ball[];
  turn: Side;
  playerGroup: Group;
  shots: number;
  last: LastShot;
  winner: '' | Side | 'draw';
  over: boolean;
}

export type KulecnikShot = { by: Side; op: 'shot'; x: number; y: number; power: number };
export type KulecnikAction = KulecnikShot | { by: 'timeout' };

export interface KulecnikResult extends RulesResult {
  playerLeft: number;
  aiLeft: number;
}

export function kulecnikConfig(t: TuningMinigamesKulecnik): KulecnikConfig {
  return {
    tableW: t.tableW,
    tableH: t.tableH,
    ballR: t.ballR,
    pockets: [...t.pockets],
    rackDx: t.rackDx,
    rackDy: t.rackDy,
    rack: [...t.rack],
    maxSpeed: t.maxSpeed,
    dec: t.dec,
    eBall: t.eBall,
    eCushion: t.eCushion,
    maxSteps: t.maxSteps,
    aiCandidates: [...t.aiCandidates],
    aiScatter: [...t.aiScatter],
    aiPowerBase: t.aiPowerBase,
    aiPowerPerM: t.aiPowerPerM,
    starLeft: [...t.starLeft],
  };
}

export const groupOf = (n: number): Group => (n >= 1 && n <= 7 ? 'solid' : n >= 9 && n <= 15 ? 'stripe' : '');
const other = (g: Group): Group => (g === 'solid' ? 'stripe' : g === 'stripe' ? 'solid' : '');
const opp = (s: Side): Side => (s === 'player' ? 'ai' : 'player');

export function groupOfSide(s: KulecnikState, side: Side): Group {
  return side === 'player' ? s.playerGroup : other(s.playerGroup);
}

/** Balls of a group still on the table. */
export function leftOf(s: KulecnikState, g: Group): number {
  return s.balls.filter((b, i) => b.on && groupOf(i) === g && g !== '').length;
}

export function headSpot(c: KulecnikConfig): { x: number; y: number } {
  return { x: Math.floor(c.tableW / 2), y: Math.floor(c.tableH / 4) };
}

export function footSpot(c: KulecnikConfig): { x: number; y: number } {
  return { x: Math.floor(c.tableW / 2), y: Math.floor((3 * c.tableH) / 4) };
}

/** Pocket p (0–5): centre and capture radius. */
export function pocket(c: KulecnikConfig, p: number): { x: number; y: number; r: number } {
  return { x: c.pockets[3 * p]!, y: c.pockets[3 * p + 1]!, r: c.pockets[3 * p + 2]! };
}

export function rackBalls(c: KulecnikConfig): Ball[] {
  const balls: Ball[] = Array.from({ length: 16 }, () => ({ x: 0, y: 0, on: true }));
  const hs = headSpot(c);
  balls[0] = { x: hs.x, y: hs.y, on: true };
  let n = 0;
  for (let k = 0; k < 5; k++) {
    for (let j = 0; j <= k; j++) {
      const id = c.rack[n++]!;
      balls[id] = {
        x: Math.floor(c.tableW / 2) + (2 * j - k) * Math.floor(c.rackDx / 2),
        y: Math.floor((3 * c.tableH) / 4) + k * c.rackDy,
        on: true,
      };
    }
  }
  return balls;
}

/** What one shot did, before the rules are applied. */
export interface ShotOutcome {
  balls: Ball[];
  firstHit: number;
  pots: number[];
}

/** Builds the world of a shot and simulates it; `onStep` (UI) sees the bodies after every step. */
export function simulateShot(
  c: KulecnikConfig,
  balls: Ball[],
  ax: number,
  ay: number,
  power: number,
  onStep?: (bodies: Body[]) => void,
): ShotOutcome {
  const W = c.tableW, H = c.tableH;
  const bodies: Body[] = balls.map((b) => ({ x: b.x, y: b.y, vx: 0, vy: 0, r: c.ballR, m: 1, on: b.on }));
  const v = shotVelocity(bodies[0]!.x, bodies[0]!.y, ax, ay, trunc(power * c.maxSpeed, 100))!;
  bodies[0]!.vx = v.vx;
  bodies[0]!.vy = v.vy;
  const pots: number[] = [];
  let firstHit = -1;
  const e = c.eCushion;
  const world: World = {
    bodies,
    statics: [
      rect(-20000, -20000, 0, H + 20000, e),
      rect(W, -20000, W + 20000, H + 20000, e),
      rect(0, -20000, W, 0, e),
      rect(0, H, W, H + 20000, e),
    ],
    eBody: c.eBall,
    capture(w) {
      w.bodies.forEach((b, i) => {
        if (!b.on) return;
        for (let p = 0; p < 6; p++) {
          const pk = pocket(c, p);
          const dx = b.x - pk.x, dy = b.y - pk.y;
          if (dx * dx + dy * dy <= pk.r * pk.r) {
            off(b);
            pots.push(i);
            return;
          }
        }
      });
      return false;
    },
    onHit(i, j) {
      if (firstHit < 0 && i === 0) firstHit = j;
    },
    dec: () => c.dec,
  };
  simulate(world, c.maxSteps, onStep && ((w) => onStep(w.bodies)));
  return { balls: bodies.map((b) => ({ x: b.x, y: b.y, on: b.on })), firstHit, pots };
}

/** Step 7: first free spot along the line (n = 0…8), else n = 0. */
function respot(c: KulecnikConfig, balls: Ball[], id: number, x: number, y0: number, dy: number): void {
  const r2 = 4 * c.ballR * c.ballR;
  for (let n = 0; n <= 8; n++) {
    const y = y0 + n * dy;
    if (balls.every((b) => !b.on || (b.x - x) ** 2 + (b.y - y) ** 2 >= r2)) {
      balls[id] = { x, y, on: true };
      return;
    }
  }
  balls[id] = { x, y: y0, on: true };
}

/** Applies a whole shot (simulation and rules 1–8) by `by`, ignoring whose turn it is. */
export function playShot(c: KulecnikConfig, s: KulecnikState, by: Side, ax: number, ay: number, power: number): KulecnikState {
  const out = simulateShot(c, s.balls, ax, ay, power);
  const brk = s.shots === 0;
  const group = groupOfSide(s, by);
  const pots = out.pots;
  const potted = (n: number): boolean => pots.includes(n);
  // Target balls before the shot: own group, or the eight once the group is cleared.
  const ownBefore = group === '' ? 0 : s.balls.filter((b, i) => b.on && groupOf(i) === group).length;
  let foul = potted(0) || out.firstHit < 0;
  if (!brk && !foul) {
    if (group === '') foul = out.firstHit === 8;
    else foul = ownBefore > 0 ? groupOf(out.firstHit) !== group : out.firstHit !== 8;
  }
  const balls = out.balls;
  let { over, winner, playerGroup } = s;
  if (potted(8) && !brk) {
    over = true;
    const won = !foul && group !== '' && ownBefore === 0;
    winner = won ? by : opp(by);
  }
  if (playerGroup === '' && !brk && !foul) {
    const first = pots.find((n) => groupOf(n) !== '');
    if (first !== undefined) {
      const g = groupOf(first);
      playerGroup = by === 'player' ? g : other(g);
    }
  }
  const shooterGroup = by === 'player' ? playerGroup : other(playerGroup);
  const keeps = !foul && (brk ? pots.some((n) => n !== 0) : shooterGroup !== '' && pots.some((n) => groupOf(n) === shooterGroup));
  const hs = headSpot(c), fs = footSpot(c);
  if (potted(0)) respot(c, balls, 0, hs.x, hs.y, -c.rackDx);
  if (potted(8) && brk) respot(c, balls, 8, fs.x, fs.y, c.rackDy);
  return {
    balls,
    turn: keeps ? by : opp(by),
    playerGroup,
    shots: s.shots + 1,
    last: { by, firstHit: out.firstHit, pots, foul },
    winner,
    over,
  };
}

interface Candidate {
  x: number;
  y: number;
  power: number;
  ease: number;
}

export class KulecnikRules implements Rules<KulecnikState, KulecnikAction, KulecnikResult, KulecnikConfig> {
  readonly id = 'kulecnik';
  readonly specVersion = 1;
  private cfg: KulecnikConfig | null = null;

  init(config: KulecnikConfig, _seed?: number): KulecnikState {
    this.cfg = config;
    return {
      balls: rackBalls(config),
      turn: 'player',
      playerGroup: '',
      shots: 0,
      last: { by: '', firstHit: -1, pots: [], foul: false },
      winner: '',
      over: false,
    };
  }

  get config(): KulecnikConfig {
    if (!this.cfg) throw new Error('kulecnik: init first');
    return this.cfg;
  }

  legalActions(): KulecnikAction[] {
    return [];
  }

  apply(s: KulecnikState, a: KulecnikAction): KulecnikState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return this.timeout(s);
    const cue = s.balls[0]!;
    if (
      a.op !== 'shot' || a.by !== s.turn ||
      !Number.isInteger(a.x) || !Number.isInteger(a.y) || !Number.isInteger(a.power) ||
      a.power < 1 || a.power > 100 || (a.x === cue.x && a.y === cue.y)
    ) throw new IllegalAction(this.id, a);
    return playShot(this.config, s, a.by, a.x, a.y, a.power);
  }

  private timeout(s: KulecnikState): KulecnikState {
    let winner: KulecnikState['winner'] = 'draw';
    if (s.playerGroup !== '') {
      const p = leftOf(s, s.playerGroup), q = leftOf(s, other(s.playerGroup));
      winner = p < q ? 'player' : q < p ? 'ai' : 'draw';
    }
    return { ...s, over: true, winner };
  }

  /** The AI's candidate shots before sorting (specs "AI" 1–3). */
  candidates(s: KulecnikState): { list: Candidate[]; targets: number[] } {
    const c = this.config;
    const balls = s.balls;
    const C = balls[0]!;
    if (s.shots === 0) {
      const t = balls[c.rack[0]!]!;
      return { list: [{ x: t.x, y: t.y, power: 100, ease: 0 }], targets: [c.rack[0]!] };
    }
    const g = groupOfSide(s, 'ai');
    let targets: number[];
    if (g !== '') {
      targets = balls.map((b, i) => (b.on && groupOf(i) === g ? i : -1)).filter((i) => i >= 0);
      if (targets.length === 0) targets = [8];
    } else {
      targets = balls.map((b, i) => (b.on && i >= 1 && i !== 8 ? i : -1)).filter((i) => i >= 0);
    }
    const list: Candidate[] = [];
    const d = 2 * c.ballR;
    for (const ti of targets) {
      const T = balls[ti]!;
      for (let p = 0; p < 6; p++) {
        const P = pocket(c, p);
        const L = isqrt((P.x - T.x) ** 2 + (P.y - T.y) ** 2);
        if (L === 0) continue;
        const gx = T.x - trunc((P.x - T.x) * d, L), gy = T.y - trunc((P.y - T.y) * d, L);
        const Lc = isqrt((gx - C.x) ** 2 + (gy - C.y) ** 2);
        if (Lc === 0) continue;
        const ease = Lc + L;
        const power = clamp(c.aiPowerBase + trunc(ease * c.aiPowerPerM, 100000), 15, 100);
        list.push({ x: gx, y: gy, power, ease });
      }
    }
    return { list, targets };
  }

  /** Value of a simulated AI shot (specs "AI" 5). */
  private value(before: KulecnikState, after: KulecnikState): number {
    if (after.over) return after.winner === 'ai' ? 100000 : -100000;
    if (after.last.foul) return -1000;
    const pots = after.last.pots;
    const g = groupOfSide(after, 'ai');
    const n = before.shots === 0 ? pots.filter((i) => i !== 0).length : g === '' ? 0 : pots.filter((i) => groupOf(i) === g).length;
    return 100 * n + (after.turn === 'ai' ? 10 : 0);
  }

  aiAction(s: KulecnikState, level: number, ai: Prng): KulecnikAction {
    const c = this.config;
    const { list, targets } = this.candidates(s);
    const sorted = list.map((k, i) => ({ k, i })).sort((a, b) => a.k.ease - b.k.ease || a.i - b.i).map((e) => e.k);
    const tried = sorted.slice(0, c.aiCandidates[level - 1]!);
    let best: { x: number; y: number; power: number };
    if (tried.length === 0) {
      const t = s.balls[targets[0] ?? 8]!;
      best = { x: t.x, y: t.y, power: 50 };
    } else {
      let bestV = -Infinity;
      best = tried[0]!;
      for (const k of tried) {
        const v = this.value(s, playShot(c, s, 'ai', k.x, k.y, k.power));
        if (v > bestV) {
          bestV = v;
          best = k;
        }
      }
    }
    const cue = s.balls[0]!;
    const sc = c.aiScatter[level - 1]!;
    const n = normalizedAim(cue.x, cue.y, best.x, best.y) ?? { x: best.x, y: best.y };
    const ex = ai.nextInt(2 * sc + 1) - sc;
    const ey = ai.nextInt(2 * sc + 1) - sc;
    return { by: 'ai', op: 'shot', x: n.x + ex, y: n.y + ey, power: best.power };
  }

  result(s: KulecnikState): KulecnikResult | null {
    if (!s.over) return null;
    const open = s.playerGroup === '';
    const playerLeft = open ? 7 : leftOf(s, s.playerGroup);
    const aiLeft = open ? 7 : leftOf(s, other(s.playerGroup));
    const winner = s.winner === '' ? 'draw' : s.winner;
    const sl = this.config.starLeft;
    const stars = winner !== 'player' ? 0 : aiLeft >= sl[0]! ? 3 : aiLeft >= sl[1]! ? 2 : 1;
    return { winner, stars, score: 7 - playerLeft, playerLeft, aiLeft };
  }
}
