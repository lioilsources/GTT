import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

import { ART_CACHE_SIZE, ArtIndex, expressionFor, Lru } from '../src/art/rules';
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
