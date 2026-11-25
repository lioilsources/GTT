import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { art, loadArt, setArt, setArtCity } from '../src/art';
import { ART_CACHE_SIZE, ArtIndex, expressionFor, type Expression, Lru } from '../src/art/rules';
import { cityIdValues } from '../src/gen/ids';
import { Tuning } from '../src/gen/tuning';

const root = join(__dirname, '..', '..');
const npc = Tuning.fromJson(parse(readFileSync(join(root, 'content/tuning.yaml'), 'utf8'))).npc;

describe('art expression (specs/art.md)', () => {
  it('happy at contactMinVibe and above, annoyed below vibeStart, else neutral', () => {
    const t = { vibeStart: 3, contactMinVibe: 7 };
    expect(expressionFor(7, t)).toBe('happy');
    expect(expressionFor(10, t)).toBe('happy');
    expect(expressionFor(6, t)).toBe('neutral');
    expect(expressionFor(3, t)).toBe('neutral');
    expect(expressionFor(2, t)).toBe('annoyed');
    expect(expressionFor(-1, t)).toBe('annoyed');
  });

  it('uses the tuning thresholds: a fresh character (vibeStart) is neutral', () => {
    expect(npc.contactMinVibe).toBeGreaterThan(npc.vibeStart);
    expect(expressionFor(npc.vibeStart, npc)).toBe('neutral');
    expect(expressionFor(npc.vibeStart - 1, npc)).toBe('annoyed');
    expect(expressionFor(npc.contactMinVibe, npc)).toBe('happy');
  });
});

describe('art index lookups', () => {
  const idx = new ArtIndex([
    'npc/maya.png', 'npc/maya_happy.png', 'npc/maya_bust.png',
    'npc/theo_neutral.png',
    'postcards/nyc/empire_state.png',
  ]);

  it('portrait: expression file, then <id>.png, then null (initials)', () => {
    expect(idx.portrait('maya', 'happy')).toBe('npc/maya_happy.png');
    expect(idx.portrait('maya', 'annoyed')).toBe('npc/maya.png');
    expect(idx.portrait('theo', 'neutral')).toBe('npc/theo_neutral.png');
    expect(idx.portrait('theo', 'happy')).toBeNull();
    expect(idx.portrait('ray', 'neutral')).toBeNull();
  });

  it('avatar, bust and postcard only when indexed', () => {
    expect(idx.avatar('maya')).toBe('npc/maya.png');
    expect(idx.avatar('theo')).toBeNull();
    expect(idx.bust('maya')).toBe('npc/maya_bust.png');
    expect(idx.bust('theo')).toBeNull();
    expect(idx.postcard('nyc', 'empire_state')).toBe('postcards/nyc/empire_state.png');
    expect(idx.postcard('prague', 'empire_state')).toBeNull();
    expect(idx.postcard('nyc', 'chrysler')).toBeNull();
  });

  it('a dropped (failed) file falls back to the next one', () => {
    const i = new ArtIndex(['npc/maya.png', 'npc/maya_happy.png']);
    i.drop('npc/maya_happy.png');
    expect(i.portrait('maya', 'happy')).toBe('npc/maya.png');
    i.drop('npc/maya.png');
    expect(i.portrait('maya', 'happy')).toBeNull();
  });

  it('parse: a missing or malformed index.json = no art', () => {
    expect(ArtIndex.parse(null).size).toBe(0);
    expect(ArtIndex.parse({ files: [] }).size).toBe(0);
    expect(ArtIndex.parse(['npc/a.png', 3, 'npc/b.png']).size).toBe(2);
    expect(new ArtIndex().portrait('maya', 'happy')).toBeNull();
  });

  it('covers the synced asset index when present', () => {
    let list: unknown;
    try {
      list = JSON.parse(readFileSync(join(__dirname, '..', 'public/shared/assets/index.json'), 'utf8'));
    } catch {
      return; // metro sync not run: nothing to check
    }
    const i = ArtIndex.parse(list);
    expect(Array.isArray(list)).toBe(true);
    expect([...(list as string[])].sort()).toEqual(list);
    for (const p of list as string[]) expect(i.has(p)).toBe(true);
  });
});

describe('NPC portraits per city (specs/art.md v4)', () => {
  const files = [
    'npc/maya.png', 'npc/maya_happy.png', 'npc/maya_annoyed.png', 'npc/maya_bust.png',
    'npc/theo.png', 'npc/theo_happy.png', 'npc/theo_bust.png',
    'npc/tokyo/maya.png', 'npc/tokyo/maya_happy.png', 'npc/tokyo/maya_bust.png',
    'npc/prague/maya.png',
  ];

  it('the city file wins: dialogue portrait, contacts / rival, feed and booth bust', () => {
    const i = new ArtIndex(files, 'tokyo');
    expect(i.portrait('maya', 'happy')).toBe('npc/tokyo/maya_happy.png');
    expect(i.avatar('maya')).toBe('npc/tokyo/maya.png');
    expect(i.bust('maya')).toBe('npc/tokyo/maya_bust.png');
  });

  it('falls back to the shared file, character by character and file by file', () => {
    const tokyo = new ArtIndex(files, 'tokyo');
    expect(tokyo.portrait('theo', 'happy')).toBe('npc/theo_happy.png');
    expect(tokyo.avatar('theo')).toBe('npc/theo.png');
    expect(tokyo.bust('theo')).toBe('npc/theo_bust.png');
    const prague = new ArtIndex(files, 'prague');
    expect(prague.avatar('maya')).toBe('npc/prague/maya.png');
    expect(prague.bust('maya')).toBe('npc/maya_bust.png');
    expect(prague.bust('ray')).toBeNull();
    expect(prague.portrait('ray', 'neutral')).toBeNull();
  });

  it('the local look wins over the expression: city <id>.png before the shared expression', () => {
    const i = new ArtIndex(files, 'tokyo');
    expect(i.portrait('maya', 'annoyed')).toBe('npc/tokyo/maya.png');
    expect(new ArtIndex(files, 'prague').portrait('maya', 'happy')).toBe('npc/prague/maya.png');
  });

  it('New York (no npc/nyc/ folder) and no city keep the shared files', () => {
    for (const city of ['nyc', null]) {
      const i = new ArtIndex(files, city);
      expect(i.portrait('maya', 'happy')).toBe('npc/maya_happy.png');
      expect(i.portrait('maya', 'neutral')).toBe('npc/maya.png');
      expect(i.avatar('maya')).toBe('npc/maya.png');
      expect(i.bust('maya')).toBe('npc/maya_bust.png');
    }
  });

  it('a city switch changes the lookups; a dropped city file falls back to the shared one', () => {
    const i = new ArtIndex(files);
    expect(i.bust('maya')).toBe('npc/maya_bust.png');
    i.city = 'tokyo';
    expect(i.bust('maya')).toBe('npc/tokyo/maya_bust.png');
    i.drop('npc/tokyo/maya_bust.png');
    expect(i.bust('maya')).toBe('npc/maya_bust.png');
    i.city = 'nyc';
    expect(i.avatar('maya')).toBe('npc/maya.png');
  });

  it('the art in the repo: Prague, Tokyo and Moscow have every character, New York the shared set', () => {
    const dir = join(root, 'assets/npc');
    const list = (readdirSync(dir, { recursive: true }) as string[])
      .map((p) => `npc/${p.split('\\').join('/')}`)
      .filter((p) => p.endsWith('.png'));
    const chars = (parse(readFileSync(join(root, 'content/npc/characters.yaml'), 'utf8')) as { characters: { id: string }[] })
      .characters.map((c) => c.id);
    expect(chars.length).toBeGreaterThan(0);
    const exprs: Expression[] = ['happy', 'neutral', 'annoyed'];
    for (const city of cityIdValues) {
      const i = new ArtIndex(list, city);
      const dirOf = city === 'nyc' ? 'npc' : `npc/${city}`;
      for (const id of chars) {
        expect(i.avatar(id)).toBe(`${dirOf}/${id}.png`);
        expect(i.bust(id)).toBe(`${dirOf}/${id}_bust.png`);
        for (const e of exprs) expect(i.portrait(id, e)).toBe(`${dirOf}/${id}_${e}.png`);
      }
    }
  });
});

describe('art city of the page (setArtCity)', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    setArt(new ArtIndex());
  });

  it('survives loadArt: set before the index arrives, kept when it is missing', async () => {
    setArt(new ArtIndex());
    setArtCity('tokyo');
    vi.stubGlobal('fetch', async () => ({ ok: true, json: async () => ['npc/maya_bust.png', 'npc/tokyo/maya_bust.png'] }));
    await loadArt('base/');
    expect(art().city).toBe('tokyo');
    expect(art().bust('maya')).toBe('npc/tokyo/maya_bust.png');
    setArtCity('nyc');
    expect(art().bust('maya')).toBe('npc/maya_bust.png');
    vi.stubGlobal('fetch', async () => { throw new Error('offline'); });
    await loadArt('base/');
    expect(art().city).toBe('nyc');
    expect(art().bust('maya')).toBeNull();
  });
});

describe('art LRU', () => {
  it('evicts the least recently used beyond capacity; get refreshes', () => {
    const evicted: string[] = [];
    const lru = new Lru<string, number>(3, (k) => evicted.push(k));
    lru.set('a', 1);
    lru.set('b', 2);
    lru.set('c', 3);
    expect(lru.get('a')).toBe(1); // a is now most recent
    lru.set('d', 4);
    expect(evicted).toEqual(['b']);
    expect(lru.has('b')).toBe(false);
    expect(lru.keys()).toEqual(['c', 'a', 'd']);
    lru.set('c', 30); // re-set refreshes without growing
    expect(lru.size).toBe(3);
    expect(lru.keys()).toEqual(['a', 'd', 'c']);
    expect(lru.get('zz')).toBeUndefined();
  });

  it('holds 24 decoded images', () => {
    const lru = new Lru<number, number>(ART_CACHE_SIZE);
    for (let i = 0; i < 30; i++) lru.set(i, i);
    expect(ART_CACHE_SIZE).toBe(24);
    expect(lru.size).toBe(24);
    expect(lru.keys()[0]).toBe(6);
  });
});
