import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { carIdValues, cityIdValues } from '../src/gen/ids';
import type { Save } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { composeSave, normalizeSave, saveConfig } from '../src/loop/save';
import { MemorySaveStore } from '../src/loop/store';
import {
  cityPassportPercent,
  cityUrl,
  LAST_CITY_KEY,
  passportPercent,
  pickStartCity,
  readLastCity,
  switchCity,
  writeLastCity,
  type KeyValue,
} from '../src/travel/cities';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));

class FakeStorage implements KeyValue {
  readonly data = new Map<string, string>();
  getItem(k: string): string | null {
    return this.data.get(k) ?? null;
  }
  setItem(k: string, v: string): void {
    this.data.set(k, v);
  }
}

describe('start city (specs/cities.md "Výchozí město")', () => {
  const known = ['nyc', 'prague'] as const;

  it('?city wins when known', () => {
    expect(pickStartCity('prague', 'nyc', known)).toBe('prague');
    expect(pickStartCity('nyc', 'prague', known)).toBe('nyc');
  });

  it('falls back to the last city, then the first bundled one', () => {
    expect(pickStartCity(null, 'prague', known)).toBe('prague');
    expect(pickStartCity('atlantis', 'prague', known)).toBe('prague');
    expect(pickStartCity('', null, known)).toBe('nyc');
    expect(pickStartCity('atlantis', 'gotham', known)).toBe('nyc');
    expect(pickStartCity(undefined, undefined, known)).toBe('nyc');
  });

  it('first bundled city is nyc', () => {
    expect(pickStartCity(null, null, cityIdValues)).toBe('nyc');
  });

  it('every generated city is selectable by ?city (Tokyo since M4)', () => {
    for (const id of cityIdValues) expect(pickStartCity(id, null, cityIdValues)).toBe(id);
    expect(cityIdValues as readonly string[]).toContain('tokyo');
  });

  it('last city round trip through storage', () => {
    const s = new FakeStorage();
    expect(readLastCity(s)).toBeNull();
    writeLastCity('prague', s);
    expect(s.data.get(LAST_CITY_KEY)).toBe('prague');
    expect(readLastCity(s)).toBe('prague');
    s.setItem(LAST_CITY_KEY, 'gotham');
    expect(readLastCity(s)).toBeNull();
    expect(readLastCity(null)).toBeNull();
    const broken: KeyValue = {
      getItem: () => {
        throw new Error('blocked');
      },
      setItem: () => {
        throw new Error('blocked');
      },
    };
    expect(readLastCity(broken)).toBeNull();
    expect(() => writeLastCity('nyc', broken)).not.toThrow();
  });
});

describe('Travel URL', () => {
  it('replaces city and keeps the other parameters', () => {
    const u = new URL(cityUrl('https://example.test/game/?city=nyc&scheme=b&debug', 'prague'));
    expect(u.pathname).toBe('/game/');
    expect(u.searchParams.get('city')).toBe('prague');
    expect(u.searchParams.get('scheme')).toBe('b');
    expect(u.searchParams.has('debug')).toBe(true);
    expect(new URL(cityUrl('https://example.test/?lang=cs', 'nyc')).searchParams.get('city')).toBe('nyc');
  });
});

describe('switch NYC → Prague → NYC keeps both saves', () => {
  it('round trip', async () => {
    const store = new MemorySaveStore();
    const storage = new FakeStorage();
    let href = 'https://example.test/?scheme=a';

    // One "page load": pick the city, load its save, remember it as the last city.
    const boot = async (): Promise<{ cityId: string; save: Save }> => {
      const cityId = pickStartCity(new URL(href).searchParams.get('city'), readLastCity(storage), cityIdValues);
      const save = normalizeSave(saveConfig(tuning, cityId, carIdValues), await store.read(cityId));
      writeLastCity(cityId, storage);
      return { cityId, save };
    };
    const travel = async (from: { cityId: string; save: Save }, to: string): Promise<void> => {
      await switchCity(to, {
        save: () => store.write(from.cityId, from.save),
        navigate: (url) => (href = url),
        href,
      });
    };
    const play = (s: { cityId: string; save: Save }, cash: number, stamps: string[]): { cityId: string; save: Save } => ({
      cityId: s.cityId,
      save: composeSave(saveConfig(tuning, s.cityId, carIdValues), { ...s.save, stamps: [...s.save.stamps, ...stamps], cash }),
    });

    let game = await boot();
    expect(game.cityId).toBe('nyc');
    game = play(game, 1234, ['district:soho']);
    await travel(game, 'prague');

    game = await boot();
    expect(game.cityId).toBe('prague');
    expect(game.save.cash).toBe(tuning.cars.startCash);
    expect(game.save.stamps).toEqual([]);
    game = play(game, 777, ['district:zizkov']);
    await travel(game, 'nyc');

    game = await boot();
    expect(game.cityId).toBe('nyc');
    expect(game.save.cash).toBe(1234);
    expect(game.save.stamps).toEqual(['district:soho']);
    expect(new URL(href).searchParams.get('scheme')).toBe('a');

    const prague = normalizeSave(saveConfig(tuning, 'prague', carIdValues), await store.read('prague'));
    expect(prague.cash).toBe(777);
    expect(prague.stamps).toEqual(['district:zizkov']);
    expect(readLastCity(storage)).toBe('nyc');
  });

  it('navigates even when the save fails', async () => {
    let url = '';
    await switchCity('prague', { save: () => Promise.reject(new Error('full')), navigate: (u) => (url = u), href: 'https://example.test/' });
    expect(new URL(url).searchParams.get('city')).toBe('prague');
  });
});

describe('Travel passport percent', () => {
  it('uses the passport rules on that city catalog', () => {
    const city = { landmarks: [], districts: ['Žižkov', 'Malá Strana'], spotMinigames: [] };
    expect(passportPercent(city, tuning.passport, [])).toBe(0);
    expect(passportPercent(city, tuning.passport, ['district:zizkov'])).toBe(50);
    expect(passportPercent(city, tuning.passport, ['district:zizkov', 'district:mala_strana'])).toBe(100);
    expect(passportPercent(city, tuning.passport, ['district:soho'])).toBe(0);
  });

  it('a city without a save is 0 % and downloads nothing', async () => {
    let opened = 0;
    const pct = await cityPassportPercent('prague', tuning, new MemorySaveStore(), () => {
      opened++;
      return Promise.reject(new Error('no pack'));
    });
    expect(pct).toBe(0);
    expect(opened).toBe(0);
  });
});
