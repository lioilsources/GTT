import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { CarFleet } from '../src/cars/fleet';
import { DriveWorld } from '../src/drive/driveWorld';
import { carIdValues, cityIdValues } from '../src/gen/ids';
import type { CarSpec, Save } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { composeSave, normalizeSave, saveConfig } from '../src/loop/save';
import { MemorySaveStore } from '../src/loop/store';
import { pickStartCity, readLastCity, switchCity, writeLastCity, type KeyValue } from '../src/travel/cities';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk, type ChunkData } from '../src/world/chunk';
import { City } from '../src/world/model';

// Soak M3-A3 (specs/cities.md "Testy"): switch through every CityId in order (NYC → Prague → Tokyo → Moscow
// → NYC …) 10 times without a crash,
// each city keeps its own save, and the physics world returns to its baseline body count after
// the city's chunks, parked cars, traffic and trams are torn down (no leaked bodies).

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const specs = new Map<string, CarSpec>(
  readdirSync(join(root, 'content', 'cars')).map((f) => {
    const s = JSON.parse(readFileSync(join(root, 'content', 'cars', f), 'utf8')) as CarSpec;
    return [s.id, s];
  }),
);
const packDir = (id: string): string => join(root, 'build', 'packs', id);
// Files are read once (slow disk); every round still decodes a fresh City from the bytes.
const bytes = new Map<string, Uint8Array>();
const source = (id: string): PackSource => ({
  read: async (p) => {
    const k = `${id}/${p}`;
    let b = bytes.get(k);
    if (!b) bytes.set(k, (b = new Uint8Array(readFileSync(join(packDir(id), p)))));
    return b;
  },
});

class FakeStorage implements KeyValue {
  readonly data = new Map<string, string>();
  getItem(k: string): string | null {
    return this.data.get(k) ?? null;
  }
  setItem(k: string, v: string): void {
    this.data.set(k, v);
  }
}

const ROUNDS = 10;
/** Every city of the build, in CityId order (no hardcoded list, plans/M4_TOKIO.md bod 2). */
const cities: readonly string[] = cityIdValues;
const roundsOf = (i: number): number => Math.ceil((ROUNDS - i) / cities.length);
const SIM_S = 3;
const dt = 1 / 60;

describe.skipIf(cities.length < 2 || !cities.every((id) => existsSync(packDir(id))))('soak: city switch 10× (M3-A3)', () => {
  it('no throw, own saves, physics bodies back to baseline every round', async () => {
    const store = new MemorySaveStore();
    const storage = new FakeStorage();
    let href = `https://example.test/?city=${cities[0]}`;
    const expected: Record<string, { cash: number; stamps: string[] }> = {};
    const baselines: Record<string, number[]> = {};
    const peaks: Record<string, number[]> = {};

    for (let round = 0; round < ROUNDS; round++) {
      // Page load: pick the city, load its save and pack, build the drive world like main.ts.
      const cityId = pickStartCity(new URL(href).searchParams.get('city'), readLastCity(storage), cityIdValues);
      expect(cityId).toBe(cities[round % cities.length]);
      const cfg = saveConfig(tuning, cityId, carIdValues);
      const save: Save = normalizeSave(cfg, await store.read(cityId));
      const want = expected[cityId] ?? { cash: tuning.cars.startCash, stamps: [] };
      expect(save.cash, `round ${round} ${cityId} cash`).toBe(want.cash);
      expect(save.stamps, `round ${round} ${cityId} stamps`).toEqual(want.stamps);
      writeLastCity(cityId, storage);

      const src = source(cityId);
      const city = await City.load(src);
      expect(city.id).toBe(cityId);
      const drive = new DriveWorld(city, specs.get(tuning.cars.startCar)!, tuning);
      const garageSpot = city.spots.items.find((s) => s.kind === 'garage');
      const fleet = new CarFleet(drive, specs, tuning, garageSpot
        ? { id: garageSpot.id, x: garageSpot.parkX / 10, y: garageSpot.parkY / 10, heading: garageSpot.parkHeading }
        : null);
      const baseline = drive.world.getBodyCount();

      const cx = Math.floor(city.startX / city.chunkM), cy = Math.floor(city.startY / city.chunkM);
      const chunks: ChunkData[] = [];
      for (const c of city.manifest.chunks) {
        if (Math.abs(c.x - cx) <= 1 && Math.abs(c.y - cy) <= 1) chunks.push(await prepareChunk(await src.read(chunkPath(c.x, c.y))));
      }
      expect(chunks.length).toBeGreaterThan(0);
      for (const c of chunks) {
        drive.addChunk(c);
        fleet.addChunk(c);
      }
      drive.input.brake = 1;
      let peak = 0;
      for (let i = 0; i < SIM_S / dt; i++) {
        drive.update(dt);
        fleet.update();
        peak = Math.max(peak, drive.world.getBodyCount());
      }
      expect(peak).toBeGreaterThan(baseline);

      // Play: this city earns its own cash and stamp.
      const played = composeSave(cfg, { ...save, cash: save.cash + 100 + round, stamps: [...save.stamps, `district:r${round}`] });
      expected[cityId] = { cash: played.cash, stamps: played.stamps };

      // Travel: save, navigate, tear the city down.
      const next = cities[(round + 1) % cities.length]! as typeof cityId;
      await switchCity(next, { save: () => store.write(cityId, played), navigate: (u) => (href = u), href });
      for (const c of chunks) {
        fleet.removeChunk(c);
        drive.removeChunk(c);
      }
      drive.traffic?.reset();
      drive.trams?.reset();
      const after = drive.world.getBodyCount();
      expect(after, `round ${round} ${cityId}: bodies after teardown`).toBe(baseline);
      (baselines[cityId] ??= []).push(baseline);
      (peaks[cityId] ??= []).push(peak);
    }

    // Same baseline every round per city: nothing accumulates across switches.
    cities.forEach((id, i) => {
      expect(baselines[id]!.length).toBe(roundsOf(i));
      expect(new Set(baselines[id]).size, `${id} baselines ${baselines[id]!.join(',')}`).toBe(1);
    });
    // Every save survives the whole soak.
    for (const [i, id] of cities.entries()) {
      const s = normalizeSave(saveConfig(tuning, id, carIdValues), await store.read(id));
      expect(s.cash).toBe(expected[id]!.cash);
      expect(s.stamps).toEqual(expected[id]!.stamps);
      expect(s.stamps.length).toBe(roundsOf(i));
    }
  }, 600000);
});
