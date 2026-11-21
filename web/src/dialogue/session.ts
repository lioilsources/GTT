import type { NpcBeat, NpcCharacter, NpcPack, NpcSkit } from '../gen/schema';
import type { TuningNpc } from '../gen/tuning';
import type { MinigameOpponent } from '../minigames/api';
import { DialogueRules, dialogueConfig, quipIndex, quipOutcome, text, type DialogueResult, type DialogueState, type NpcContext, type Tone } from './rules';

/**
 * One play session of NPC dialogue (specs/dialogue.md): the rules state (vibe, contacts, recent
 * skits) plus the content to show. Pure: no DOM. Other features call `startSkit` and mount the UI
 * (`mountDialogue`) on top.
 */
export class DialogueSession {
  readonly rules: DialogueRules;
  state: DialogueState;
  private readonly chars = new Map<string, NpcCharacter>();
  private readonly skits = new Map<string, NpcSkit>();

  constructor(readonly pack: NpcPack, readonly tuning: TuningNpc, city: string, seed: number) {
    const cfg = dialogueConfig(pack, tuning, city);
    this.rules = new DialogueRules();
    this.state = this.rules.init(cfg, seed);
    for (const c of pack.characters) this.chars.set(c.id, c);
    for (const s of pack.skits) this.skits.set(s.id, s);
  }

  character(id: string): NpcCharacter | undefined {
    return this.chars.get(id);
  }

  canStart(characterId: string, context: NpcContext): boolean {
    return this.state.skit === '' && this.rules.candidates(characterId, context).length > 0;
  }

  /** Picks and starts a skit; false when none fits (or one is running). */
  startSkit(characterId: string, context: NpcContext): boolean {
    if (!this.canStart(characterId, context)) return false;
    this.state = this.rules.apply(this.state, { by: 'player', type: 'start', character: characterId, context });
    return true;
  }

  get running(): boolean {
    return this.state.skit !== '';
  }

  /** The skit running now, or the one that just ended. */
  get skit(): NpcSkit | undefined {
    return this.skits.get(this.state.skit || this.state.last);
  }

  /** The beat waiting for a reply (undefined when the skit is over). */
  get beat(): NpcBeat | undefined {
    return this.running ? this.skit?.beats[this.state.beat] : undefined;
  }

  reply(tone: Tone): void {
    this.state = this.rules.apply(this.state, { by: 'player', type: 'reply', tone });
  }

  leave(): void {
    if (this.running) this.state = this.rules.apply(this.state, { by: 'player', type: 'leave' });
  }

  result(): DialogueResult | null {
    return this.rules.result(this.state);
  }

  vibe(characterId: string): number {
    return this.state.vibe[characterId] ?? 0;
  }

  /** The minigame opponent for the result screen (MinigameContext.opponentId). */
  opponent(characterId: string | undefined, seed: number, locale: string): MinigameOpponent | undefined {
    const c = characterId ? this.chars.get(characterId) : undefined;
    return c ? opponentOf(c, seed, locale) : undefined;
  }
}

export function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w[0]!.toUpperCase())
    .join('')
    .slice(0, 2);
}

export function opponentOf(c: NpcCharacter, seed: number, locale: string): MinigameOpponent {
  return {
    id: c.id,
    name: c.name,
    portrait: c.portrait,
    line: (winner) => {
      const list = c.quips[quipOutcome(winner)];
      return text(list[quipIndex(list.length, seed)]!, locale);
    },
  };
}

let shared: DialogueSession | null = null;

/** The app-wide session (kept in memory until saving arrives with M1 item 11). */
export function dialogueSession(): DialogueSession | null {
  return shared;
}

export function setDialogueSession(s: DialogueSession | null): void {
  shared = s;
}
