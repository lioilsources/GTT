import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

import { messages } from '../src/gen/i18n';
import { Tuning } from '../src/gen/tuning';
import { fnv1a, postcardShapes } from '../src/passport/postcard';
import { districtId, PassportRules } from '../src/passport/rules';
import { PassportTracker, passportCity, type PassportCity } from '../src/passport/tracker';
import type { PackSource } from '../src/world/citypack';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const cfg = {
  landmarks: ['a', 'b'],
  districts: ['d1', 'd2'],
  minigames: ['sirky'],
  photos: [],
  weights: [3, 1, 3, 2],
  starsForStamp: 3,
};

describe('passport rules', () => {
  const r = new PassportRules();

  it('counts points and floors the percent', () => {
    let s = r.init(cfg);
    expect(s.total).toBe(11);
    s = r.apply(s, { by: 'player', op: 'visit', kind: 'landmark', id: 'a' });
    expect(s.last).toBe('landmark:a');
    expect(r.result(s).percent).toBe(27);
    s = r.apply(s, { by: 'player', op: 'visit', kind: 'landmark', id: 'a' });
    expect(s.last).toBe('');
    expect(s.points).toBe(3);
  });

  it('stamps a minigame only at 3 stars', () => {
    let s = r.init(cfg);
    s = r.apply(s, { by: 'player', op: 'visit', kind: 'minigame', id: 'sirky', stars: 2 });
    expect(s.stamps).toEqual([]);
    s = r.apply(s, { by: 'player', op: 'visit', kind: 'minigame', id: 'sirky', stars: 3 });
    expect(s.stamps).toEqual(['minigame:sirky']);
  });

  it('rejects unknown ids and bad stars', () => {
    const s = r.init(cfg);
    expect(() => r.apply(s, { by: 'player', op: 'visit', kind: 'landmark', id: 'zz' })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'visit', kind: 'minigame', id: 'sirky', stars: 4 })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'visit', kind: 'minigame', id: 'sirky' })).toThrow();
  });

  it('restores saved stamps and lists the missing ones', () => {
    const s = r.init({ ...cfg, stamps: ['district:d2', 'landmark:x', 'district:d2'] });
    expect(s.stamps).toEqual(['district:d2']);
    expect(r.legalActions(s).map((a) => `${a.kind}:${a.id}`)).toEqual(['landmark:a', 'landmark:b', 'district:d1', 'minigame:sirky']);
  });

  it('district ids', () => {
    expect(districtId("Hell's Kitchen")).toBe('hells_kitchen');
    expect(districtId('DUMBO')).toBe('dumbo');
    expect(districtId('Upper West Side')).toBe('upper_west_side');
    expect(districtId(' St. Mark’s  Place ')).toBe('st_marks_place');
  });

  it('district ids transliterate diacritics', () => {
    expect(districtId('Žižkov')).toBe('zizkov');
    expect(districtId('Malá Strana')).toBe('mala_strana');
    expect(districtId('Staré Město')).toBe('stare_mesto');
    expect(districtId('Košíře–Motol')).toBe('kosire_motol');
    expect(districtId('Straße')).toBe('strasse');
  });
});

describe('postcard picture', () => {
  it('fnv1a', () => {
    expect(fnv1a('')).toBe(0x811c9dc5);
    expect(fnv1a('a')).toBe(0xe40c292c);
  });

  it('tower with spire, low building, open space', () => {
    const tall = postcardShapes('one_wtc', 541);
    expect(tall.filter((s) => s.t === 'poly')).toHaveLength(1);
    expect(tall.filter((s) => s.t === 'rect' && s.w === 6)).toHaveLength(44);
    const low = postcardShapes('city_hall', 32);
    expect(low.filter((s) => s.t === 'poly')).toHaveLength(0);
    expect(low.filter((s) => s.t === 'rect' && s.w === 6)).toHaveLength(16);
    expect(postcardShapes('central_park', 0).filter((s) => s.t === 'circle')).toHaveLength(5);
  });
});

describe('passport tracker', () => {
  const city: PassportCity = {
    landmarks: [
      { id: 'empire_state', name: 'Empire State Building', x: 1000, y: 0, heightM: 381, hero: true },
      { id: 'chrysler', name: 'Chrysler Building', x: 1200, y: 0, heightM: 319, hero: true },
      { id: 'bryant_park', name: 'Bryant Park', x: 0, y: 0, heightM: 0, hero: false },
      { id: 'park_432', name: '432 Park Avenue', x: 0, y: 0, heightM: 426, hero: true },
    ],
    districts: ['Midtown', "Hell's Kitchen", 'Midtown'],
    spotMinigames: ['', 'sirky', 'dama', 'sirky'],
  };

  it('builds the catalog from heroes with a postcard', () => {
    const t = new PassportTracker(city, tuning.passport);
    expect(t.state.catalog).toEqual({
      landmark: ['empire_state', 'chrysler'],
      district: ['midtown', 'hells_kitchen'],
      minigame: ['sirky', 'dama'],
      photo: [],
    });
  });

  it('discovers one landmark per tick and districts by name', () => {
    const t = new PassportTracker(city, tuning.passport, ['district:midtown']);
    const seen: string[] = [];
    t.onStamp((e) => seen.push(`${e.kind}:${e.id}`));
    expect(t.update(500, 0, 'Midtown')).toEqual([]);
    t.update(110, 0, "Hell's Kitchen");
    t.update(110, 0, null);
    expect(seen).toEqual(['landmark:empire_state', 'district:hells_kitchen', 'landmark:chrysler']);
    expect(t.minigame('dama', 3)).toBe(true);
    expect(t.stamps).toEqual(['district:midtown', 'landmark:empire_state', 'district:hells_kitchen', 'landmark:chrysler', 'minigame:dama']);
  });
});

describe('postcards in i18n', () => {
  // Every city's landmarks.yaml; a postcard id belongs to exactly one city (M3: Prague joins New York).
  const cities = readdirSync(join(root, 'content', 'cities')).filter((c) => existsSync(join(root, 'content', 'cities', c, 'landmarks.yaml')));
  const byCity = new Map(
    cities.map((c) => [
      c,
      (parse(readFileSync(join(root, 'content', 'cities', c, 'landmarks.yaml'), 'utf8')) as { landmarks: Array<{ id: string; name: string; hero?: boolean }> }).landmarks,
    ]),
  );
  const ids = Object.keys(messages.en).filter((k) => /^lm_.+_title$/.test(k)).map((k) => k.slice(3, -6));

  it('each postcard is a hero landmark of one city with title (= landmarks.yaml name) and two-sentence text in both languages', () => {
    for (const id of ids) {
      const owners = cities.filter((c) => byCity.get(c)!.some((l) => l.id === id));
      expect(owners, id).toHaveLength(1);
      const lm = byCity.get(owners[0]!)!.find((l) => l.id === id)!;
      expect(lm.hero, id).toBe(true);
      for (const loc of ['en', 'cs'] as const) {
        const m = messages[loc] as Record<string, string>;
        expect(m[`lm_${id}_title`], `${loc} ${id}`).toBe(lm.name);
        expect(m[`lm_${id}_text`]?.split('. ').length, `${loc} ${id} two sentences`).toBe(2);
      }
    }
  });

  it('a city with postcards has 20 of them (M1 9, M3)', () => {
    for (const c of cities) {
      const n = byCity.get(c)!.filter((l) => ids.includes(l.id)).length;
      if (n > 0) expect(n, c).toBe(20);
    }
    expect(byCity.get('nyc')!.filter((l) => ids.includes(l.id))).toHaveLength(20);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
describe.skipIf(!existsSync(pack))('passport on the NYC pack', () => {
  it('every postcard landmark is reachable by car within the discovery radius', async () => {
    const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };
    const city = await City.load(source);
    const t = new PassportTracker(passportCity(city), tuning.passport);
    expect(t.landmarks).toHaveLength(20);
    for (const l of t.landmarks) {
      const hit = city.graph.nearest(l.x, l.y, tuning.passport.discoverRadiusM);
      expect(hit, l.id).not.toBeNull();
    }
    expect(t.state.catalog.district.length).toBeGreaterThan(30);
    expect(t.state.catalog.minigame.length).toBe(8);
  });
});

