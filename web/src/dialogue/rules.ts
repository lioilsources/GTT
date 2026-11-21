import { Prng } from '../rules/prng';
import type { TuningNpc } from '../gen/tuning';
import type { NpcPack, NpcSkit, NpcText } from '../gen/schema';
import { IllegalAction, withRng } from '../minigames/rules';

/** specs/dialogue.md, version 1. Pure: no DOM, no Babylon. */

export type Tone = 'flirt' | 'joke' | 'dry';
export type NpcContext = NpcSkit['context'];

export const tones: readonly Tone[] = ['flirt', 'joke', 'dry'];
/** Fixed context order (spec "Obsah"). */
export const contexts: readonly NpcContext[] = ['street', 'bar', 'shop', 'minigame_win', 'minigame_lose', 'crash', 'car_owner'];

export interface DialogueConfig {
  city: string;
  recentK: number;
  vibeMax: number;
  vibeStart: number;
  contactMinVibe: number;
  contactBasePct: number;
  contactStepPct: number;
  contactMaxPct: number;
  characters: Array<{ id: string; tones: Record<Tone, number> }>;
  skits: Array<{ id: string; character: string; context: string; city: string; beats: number }>;
}

export interface DialogueState {
  rng: number;
  recent: string[];
  vibe: Record<string, number>;
  contacts: string[];
  skit: string;
  character: string;
  beat: number;
  tones: Tone[];
  gained: number;
  last: string;
  completed: boolean;
  newContact: boolean;
}

export type DialogueAction =
  | { by: 'player'; type: 'start'; character: string; context: string }
  | { by: 'player'; type: 'reply'; tone: Tone }
  | { by: 'player'; type: 'leave' };

export interface DialogueResult {
  skit: string;
  character: string;
  completed: boolean;
  gained: number;
  vibe: number;
  contact: boolean;
  newContact: boolean;
}

/** Runtime config: numbers from tuning `npc.*`, pool from the merged content (skits sorted by id). */
export function dialogueConfig(pack: NpcPack, t: TuningNpc, city: string): DialogueConfig {
  const skits = [...pack.skits].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return {
    city,
    recentK: t.recentK,
    vibeMax: t.vibeMax,
    vibeStart: t.vibeStart,
    contactMinVibe: t.contactMinVibe,
    contactBasePct: t.contactBasePct,
    contactStepPct: t.contactStepPct,
    contactMaxPct: t.contactMaxPct,
    characters: pack.characters.map((c) => ({ id: c.id, tones: { flirt: c.tones.flirt, joke: c.tones.joke, dry: c.tones.dry } })),
    skits: skits.map((s) => ({ id: s.id, character: s.character, context: s.context, city: s.city ?? '', beats: s.beats.length })),
  };
}

export class DialogueRules {
  readonly id = 'dialogue';
  readonly specVersion = 1;
  private cfg: DialogueConfig | null = null;

  constructor(config?: DialogueConfig) {
    this.cfg = config ?? null;
  }

  private get c(): DialogueConfig {
    if (!this.cfg) throw new Error('dialogue: init first');
    return this.cfg;
  }

  init(config: DialogueConfig, seed: number): DialogueState {
    this.cfg = config;
    const vibe: Record<string, number> = {};
    for (const ch of config.characters) vibe[ch.id] = config.vibeStart;
    return {
      rng: new Prng(seed).state, recent: [], vibe, contacts: [], skit: '', character: '', beat: 0, tones: [], gained: 0,
      last: '', completed: false, newContact: false,
    };
  }

  /** Candidates for (character, context) in config order (spec "Výběr skitu" 1). */
  candidates(character: string, context: string): string[] {
    const c = this.c;
    return c.skits
      .filter((s) => s.character === character && s.context === context && (s.city === '' || s.city === c.city))
      .map((s) => s.id);
  }

  legalActions(s: DialogueState): DialogueAction[] {
    if (s.skit === '') {
      const out: DialogueAction[] = [];
      for (const ch of this.c.characters) {
        for (const x of contexts) if (this.candidates(ch.id, x).length > 0) out.push({ by: 'player', type: 'start', character: ch.id, context: x });
      }
      return out;
    }
    return [...tones.map((tone): DialogueAction => ({ by: 'player', type: 'reply', tone })), { by: 'player', type: 'leave' }];
  }

  apply(s: DialogueState, a: DialogueAction): DialogueState {
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    switch (a.type) {
      case 'start':
        return this.start(s, a);
      case 'reply':
        return this.reply(s, a);
      case 'leave':
        if (s.skit === '') throw new IllegalAction(this.id, a);
        return { ...s, last: s.skit, skit: '', completed: false, newContact: false };
      default:
        throw new IllegalAction(this.id, a);
    }
  }

  private start(s: DialogueState, a: { character: string; context: string }): DialogueState {
    if (s.skit !== '') throw new IllegalAction(this.id, a);
    const cand = this.candidates(a.character, a.context);
    if (cand.length === 0) throw new IllegalAction(this.id, a);
    const fresh = cand.filter((id) => !s.recent.includes(id));
    let skit: string;
    let rng = s.rng;
    if (fresh.length > 0) {
      const r = withRng(s.rng, (p) => p.nextInt(fresh.length));
      skit = fresh[r.value]!;
      rng = r.rng;
    } else {
      // Exhausted: the least recently played candidate (smallest index in the queue).
      skit = cand.reduce((best, id) => (s.recent.indexOf(id) < s.recent.indexOf(best) ? id : best));
    }
    const recent = [...s.recent.filter((id) => id !== skit), skit];
    while (recent.length > this.c.recentK) recent.shift();
    return { ...s, rng, recent, skit, character: a.character, beat: 0, tones: [], gained: 0 };
  }

  private reply(s: DialogueState, a: { tone: Tone }): DialogueState {
    if (s.skit === '' || !tones.includes(a.tone)) throw new IllegalAction(this.id, a);
    const c = this.c;
    const ch = c.characters.find((x) => x.id === s.character);
    const sk = c.skits.find((x) => x.id === s.skit);
    if (!ch || !sk) throw new IllegalAction(this.id, a);
    const old = s.vibe[s.character] ?? c.vibeStart;
    const now = Math.min(c.vibeMax, Math.max(0, old + ch.tones[a.tone]));
    const n: DialogueState = {
      ...s,
      vibe: { ...s.vibe, [s.character]: now },
      gained: s.gained + now - old,
      tones: [...s.tones, a.tone],
      beat: s.beat + 1,
    };
    if (n.beat < sk.beats) return n;
    // Skit completed: maybe a phone contact.
    let rng = n.rng;
    let contacts = n.contacts;
    let newContact = false;
    if (!contacts.includes(s.character) && now >= c.contactMinVibe) {
      const pct = Math.min(c.contactMaxPct, c.contactBasePct + (now - c.contactMinVibe) * c.contactStepPct);
      const r = withRng(rng, (p) => p.nextInt(100));
      rng = r.rng;
      if (r.value < pct) {
        contacts = [...contacts, s.character];
        newContact = true;
      }
    }
    return { ...n, rng, contacts, newContact, completed: true, last: s.skit, skit: '' };
  }

  aiAction(_s: DialogueState, _level: number, _ai: Prng): DialogueAction {
    throw new Error('dialogue: no AI');
  }

  result(s: DialogueState): DialogueResult | null {
    if (s.skit !== '' || s.last === '') return null;
    return {
      skit: s.last,
      character: s.character,
      completed: s.completed,
      gained: s.gained,
      vibe: s.vibe[s.character] ?? 0,
      contact: s.contacts.includes(s.character),
      newContact: s.newContact,
    };
  }
}

/** Player outcome on the minigame result screen → quip list (spec "Hláška soupeře"). */
export function quipOutcome(winner: 'player' | 'ai' | 'draw'): 'win' | 'lose' | 'draw' {
  return winner === 'player' ? 'win' : winner === 'ai' ? 'lose' : 'draw';
}

/** quips[outcome][Prng(seed).nextInt(n)]. */
export function quipIndex(count: number, seed: number): number {
  return new Prng(seed).nextInt(count);
}

/** The text in [locale], English when the locale is missing. */
export function text(t: NpcText, locale: string): string {
  return (t as unknown as Record<string, string | undefined>)[locale] ?? t.en;
}
