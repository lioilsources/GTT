import type { TuningFeed } from '../gen/tuning';
import { Prng } from '../rules/prng';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';

/** Feed deck selection, specs/feed.md version 1 (P0, integers only). */
export interface FeedCandidate {
  spot: string;
  game: string;
  engine: string;
  local: boolean;
  district: string;
  distDm: number;
  visits: number;
  landmark: boolean;
}

export interface FeedConfig {
  deckSize: number;
  novelty: number;
  prefStep: number;
  prefMin: number;
  prefMax: number;
  driveDmPerS: number;
  bandMinS: number;
  bandMaxS: number;
  bandPoints: number;
  nearPoints: number;
  bandFalloffS: number;
  districtBonus: number;
  landmarkBonus: number;
  jitter: number;
  hostLines: number;
  rewardBase: number;
  rewardPerMin: number;
  difficultyBase: number;
  difficultyMax: number;
  candidates: FeedCandidate[];
  prefs: Record<string, number>;
  visitedDistricts: string[];
}

export interface FeedCard {
  spot: string;
  game: string;
  engine: string;
  district: string;
  local: boolean;
  driveS: number;
  distDm: number;
  score: number;
  host: number;
  reward: number;
  difficulty: number;
}

export interface FeedState {
  deck: FeedCard[];
  at: number;
  prefs: Record<string, number>;
  liked: string[];
  accepted: string;
  over: boolean;
}

export type FeedOp = 'next' | 'like' | 'less' | 'accept';
export interface FeedAction {
  by: 'player';
  op: FeedOp;
  [k: string]: unknown;
}

export function feedConfig(
  t: TuningFeed,
  candidates: FeedCandidate[],
  prefs: Record<string, number>,
  visitedDistricts: string[],
): FeedConfig {
  return {
    deckSize: t.deckSize, novelty: t.novelty, prefStep: t.prefStep, prefMin: t.prefMin, prefMax: t.prefMax,
    driveDmPerS: t.driveDmPerS, bandMinS: t.bandMinS, bandMaxS: t.bandMaxS, bandPoints: t.bandPoints,
    nearPoints: t.nearPoints, bandFalloffS: t.bandFalloffS, districtBonus: t.districtBonus,
    landmarkBonus: t.landmarkBonus, jitter: t.jitter, hostLines: t.hostLines, rewardBase: t.rewardBase,
    rewardPerMin: t.rewardPerMin, difficultyBase: t.difficultyBase, difficultyMax: t.difficultyMax,
    candidates, prefs: { ...prefs }, visitedDistricts: [...visitedDistricts],
  };
}

const idiv = (a: number, b: number): number => Math.floor(a / b);
const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));

/** Distance band points for a drive time (specs/feed.md init step 2). */
export function bandScore(c: FeedConfig, driveS: number): number {
  if (driveS < c.bandMinS) return c.nearPoints;
  if (driveS <= c.bandMaxS) return c.bandPoints;
  return Math.max(0, c.bandPoints - idiv((driveS - c.bandMaxS) * c.bandPoints, c.bandFalloffS));
}

export class FeedRules implements Rules<FeedState, FeedAction, RulesResult, FeedConfig> {
  readonly id = 'feed';
  readonly specVersion = 1;
  private cfg: FeedConfig | null = null;

  init(config: FeedConfig, seed: number): FeedState {
    this.cfg = config;
    const c = config;
    const rng = new Prng(seed);
    const prefs: Record<string, number> = {};
    for (const k of Object.keys(c.prefs)) prefs[k] = clamp(c.prefs[k]!, c.prefMin, c.prefMax);
    const visited = new Set(c.visitedDistricts);
    const scored = c.candidates.map((k, i) => {
      const driveS = idiv(k.distDm, c.driveDmPerS);
      const score =
        (k.visits === 0 ? c.novelty : 0) +
        (prefs[k.engine] ?? 0) * c.prefStep +
        bandScore(c, driveS) +
        (k.district !== '' && !visited.has(k.district) ? c.districtBonus : 0) +
        (k.landmark ? c.landmarkBonus : 0) +
        rng.nextInt(c.jitter + 1);
      return { k, i, driveS, score };
    });
    const ranked = [...scored].sort((a, b) => b.score - a.score || a.i - b.i);
    const picked: typeof ranked = [];
    const required = [ranked.find((x) => x.k.local), ranked.find((x) => x.k.engine === 'drive')];
    for (const r of required) if (r && !picked.includes(r) && picked.length < c.deckSize) picked.push(r);
    for (const r of ranked) {
      if (picked.length >= c.deckSize) break;
      if (!picked.includes(r)) picked.push(r);
    }
    picked.sort((a, b) => ranked.indexOf(a) - ranked.indexOf(b));
    const deck = picked.map(({ k, driveS, score }) => ({
      spot: k.spot,
      game: k.game,
      engine: k.engine,
      district: k.district,
      local: k.local,
      driveS,
      distDm: k.distDm,
      score,
      host: rng.nextInt(c.hostLines),
      reward: c.rewardBase + idiv(driveS * c.rewardPerMin, 60),
      difficulty: Math.min(c.difficultyMax, c.difficultyBase + k.visits),
    }));
    return { deck, at: 0, prefs, liked: [], accepted: '', over: deck.length === 0 };
  }

  private get c(): FeedConfig {
    if (!this.cfg) throw new Error('feed: init first');
    return this.cfg;
  }

  legalActions(s: FeedState): FeedAction[] {
    if (s.over) return [];
    const card = s.deck[s.at]!;
    const ops: FeedOp[] = s.liked.includes(card.spot) ? ['next', 'less', 'accept'] : ['next', 'like', 'less', 'accept'];
    return ops.map((op) => ({ by: 'player', op }));
  }

  apply(s: FeedState, a: FeedAction): FeedState {
    if (a.by !== 'player' || !this.legalActions(s).some((x) => x.op === a.op)) throw new IllegalAction(this.id, a);
    const card = s.deck[s.at]!;
    const prefs = { ...s.prefs };
    const step = (n: FeedState): FeedState => ({ ...n, at: n.at + 1, over: n.at + 1 >= n.deck.length });
    switch (a.op) {
      case 'next':
        return step(s);
      case 'like':
        prefs[card.engine] = Math.min(this.c.prefMax, (prefs[card.engine] ?? 0) + 1);
        return { ...s, prefs, liked: [...s.liked, card.spot] };
      case 'less':
        prefs[card.engine] = Math.max(this.c.prefMin, (prefs[card.engine] ?? 0) - 1);
        return step({ ...s, prefs });
      case 'accept':
        return { ...s, accepted: card.spot, over: true };
    }
  }

  aiAction(): FeedAction {
    throw new Error('feed: no AI');
  }

  result(): RulesResult | null {
    return null;
  }
}

/** Inputs for the client-side candidate list (specs/feed.md "Kandidáti"). */
export interface CandidateSpot {
  id: string;
  minigame: string;
  /** Spot point, dm. */
  x: number;
  y: number;
}

export interface CandidateInput {
  cityId: string;
  spots: CandidateSpot[];
  catalog: Record<string, { engine: string; cities: readonly string[] }>;
  districtAt: (xDm: number, yDm: number) => string;
  /** Landmark anchors, dm. */
  landmarks: Array<{ id: string; x: number; y: number }>;
  discovered: ReadonlySet<string>;
  visits: ReadonlyMap<string, number>;
  landmarkRadiusDm: number;
  distDm: (spotId: string) => number;
}

export function buildCandidates(inp: CandidateInput): FeedCandidate[] {
  const r2 = inp.landmarkRadiusDm * inp.landmarkRadiusDm;
  const make = (s: CandidateSpot, game: string, engine: string, local: boolean): FeedCandidate => ({
    spot: s.id,
    game,
    engine,
    local,
    district: inp.districtAt(s.x, s.y),
    distDm: inp.distDm(s.id),
    visits: inp.visits.get(s.id) ?? 0,
    landmark: inp.landmarks.some((l) => !inp.discovered.has(l.id) && (l.x - s.x) ** 2 + (l.y - s.y) ** 2 <= r2),
  });
  const out: FeedCandidate[] = [];
  for (const s of inp.spots) {
    const meta = s.minigame ? inp.catalog[s.minigame] : undefined;
    if (meta) out.push(make(s, s.minigame, meta.engine, meta.cities.includes(inp.cityId)));
  }
  if (!out.some((c) => c.engine === 'drive')) {
    for (const s of inp.spots) if (!s.minigame) out.push(make(s, 'challenge', 'drive', false));
  }
  return out;
}
