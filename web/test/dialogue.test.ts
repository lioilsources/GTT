import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

import { DialogueRules, contexts, quipIndex, quipOutcome, type DialogueConfig } from '../src/dialogue/rules';
import { DialogueSession, initials, opponentOf } from '../src/dialogue/session';
import type { NpcPack } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { replay } from '../src/minigames/rules';
import { canonical, type VectorFile } from '../src/rules/vectors';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content/tuning.yaml'), 'utf8')));
const pack: NpcPack = {
  characters: parse(readFileSync(join(root, 'content/npc/characters.yaml'), 'utf8')).characters,
  skits: readdirSync(join(root, 'content/npc/skits'))
    .filter((f) => f.endsWith('.yaml'))
    .map((f) => parse(readFileSync(join(root, 'content/npc/skits', f), 'utf8'))),
};

const cfg: DialogueConfig = {
  city: 'nyc', recentK: 2, vibeMax: 10, vibeStart: 0, contactMinVibe: 4, contactBasePct: 30, contactStepPct: 20, contactMaxPct: 90,
  characters: [{ id: 'a', tones: { flirt: 3, joke: 1, dry: -2 } }],
  skits: [
    { id: 'a_street_1', character: 'a', context: 'street', city: '', beats: 2 },
    { id: 'a_street_2', character: 'a', context: 'street', city: 'prg', beats: 2 },
  ],
};

describe('dialogue rules (specs/dialogue.md)', () => {
  it('starts idle with vibeStart for every character', () => {
    const r = new DialogueRules();
    const s = r.init(cfg, 1);
    expect(s).toMatchObject({ skit: '', last: '', vibe: { a: 0 }, contacts: [], recent: [] });
    expect(r.legalActions(s)).toEqual([{ by: 'player', type: 'start', character: 'a', context: 'street' }]);
    expect(r.result(s)).toBeNull();
  });

  it('filters the pool by city and rejects illegal actions', () => {
    const r = new DialogueRules();
    const s = r.init(cfg, 1);
    expect(r.candidates('a', 'street')).toEqual(['a_street_1']);
    expect(() => r.apply(s, { by: 'player', type: 'start', character: 'a', context: 'bar' })).toThrow();
    expect(() => r.apply(s, { by: 'player', type: 'reply', tone: 'joke' })).toThrow();
    expect(() => r.apply(s, { by: 'player', type: 'leave' })).toThrow();
    const run = r.apply(s, { by: 'player', type: 'start', character: 'a', context: 'street' });
    expect(() => r.apply(run, { by: 'player', type: 'start', character: 'a', context: 'street' })).toThrow();
    expect(r.legalActions(run).map((a) => ('tone' in a ? a.tone : a.type))).toEqual(['flirt', 'joke', 'dry', 'leave']);
  });

  it('clamps vibe and counts only the real change', () => {
    const r = new DialogueRules();
    let s = r.apply(r.init(cfg, 1), { by: 'player', type: 'start', character: 'a', context: 'street' });
    s = r.apply(s, { by: 'player', type: 'reply', tone: 'dry' });
    expect(s.vibe['a']).toBe(0);
    expect(s.gained).toBe(0);
    s = r.apply(s, { by: 'player', type: 'reply', tone: 'flirt' });
    expect(r.result(s)).toMatchObject({ skit: 'a_street_1', completed: true, gained: 3, vibe: 3, newContact: false });
  });

  it('replays vectors/dialogue.json', () => {
    const v = JSON.parse(readFileSync(join(root, 'vectors/dialogue.json'), 'utf8')) as VectorFile;
    for (const c of v.cases) {
      const got = replay(new DialogueRules() as never, c);
      c.steps.forEach((st, i) => expect(canonical(got.states[i]), `${c.name} ${i}`).toBe(canonical(st.state)));
      expect(canonical(got.result), c.name).toBe(canonical(c.result));
    }
  });

  it('picks quips with Prng(seed)', () => {
    expect([1, 2, 3, 42, 1000].map((s) => quipIndex(2, s))).toEqual(QUIP_2);
    expect(quipOutcome('player')).toBe('win');
    expect(quipOutcome('ai')).toBe('lose');
    expect(quipOutcome('draw')).toBe('draw');
  });
});

// Shared with packages/npc_dialogue/test (same Prng, same expectation).
const QUIP_2 = [1, 0, 1, 0, 0];

describe('npc content', () => {
  it('has 6 adult characters and 30 skits of 5 beats', () => {
    expect(pack.characters).toHaveLength(6);
    expect(pack.characters.every((c) => c.age >= 21)).toBe(true);
    expect(pack.skits).toHaveLength(30);
    expect(pack.skits.every((s) => s.beats.length === 5)).toBe(true);
  });

  it('every character has street chat and a minigame win and lose skit', () => {
    const s = new DialogueSession(pack, tuning.npc, 'nyc', 1);
    for (const c of pack.characters) {
      for (const x of ['street', 'minigame_win', 'minigame_lose'] as const) expect(s.canStart(c.id, x), `${c.id} ${x}`).toBe(true);
    }
  });

  it('plays every skit to the end in a session', () => {
    const s = new DialogueSession(pack, tuning.npc, 'nyc', 7);
    let played = 0;
    for (const c of pack.characters) {
      for (const x of contexts) {
        for (let k = 0; k < s.rules.candidates(c.id, x).length; k++) {
          expect(s.startSkit(c.id, x)).toBe(true);
          let i = 0;
          while (s.beat) {
            expect(s.beat.npc.cs.length).toBeGreaterThan(0);
            s.reply((['flirt', 'joke', 'dry'] as const)[i++ % 3]!);
          }
          expect(s.result()?.completed).toBe(true);
          played++;
        }
      }
    }
    expect(played).toBe(30);
  });

  it('builds the opponent line in both locales', () => {
    const maya = pack.characters.find((c) => c.id === 'maya')!;
    expect(initials(maya.name)).toBe('M');
    const en = opponentOf(maya, 42, 'en');
    expect(en.line('player')).toBe(maya.quips.win[quipIndex(maya.quips.win.length, 42)]!.en);
    expect(opponentOf(maya, 42, 'cs').line('draw')).toBe(maya.quips.draw[0]!.cs);
  });
});
