import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { parse } from 'yaml';
import { beforeAll, describe, expect, it } from 'vitest';

import { CarFleet } from '../src/cars/fleet';
import { boardCandidate, generateParked, parkedPool } from '../src/cars/parked';
import { carsConfig, CarsRules, type CarsState } from '../src/cars/rules';
import { carShape, paintHex } from '../src/cars/shape';
import { DriveWorld } from '../src/drive/driveWorld';
import { carIdValues, cityIdValues } from '../src/gen/ids';
import type { CarSpec } from '../src/gen/schema';
import { tokens } from '../src/gen/tokens';
import { Tuning } from '../src/gen/tuning';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk, type ChunkData } from '../src/world/chunk';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const specs = new Map<string, CarSpec>(
  readdirSync(join(root, 'content', 'cars')).map((f) => {
    const s = JSON.parse(readFileSync(join(root, 'content', 'cars', f), 'utf8')) as CarSpec;
    return [s.id, s];
  }),
);
const prices = Object.fromEntries([...specs].map(([id, s]) => [id, s.price]));

describe('car content (specs/cars.md)', () => {
  it('M1 cars of different classes, every car tagged with known cities, paints from the tokens', () => {
    expect([...specs.keys()].sort()).toEqual([...carIdValues]);
    const m1 = ['m0_coupe', 'hatch_pip', 'muscle_brute', 'taxi_metro', 'pickup_hauler'];
    expect(new Set(m1.map((id) => specs.get(id)!.class)).size).toBe(5);
    for (const s of specs.values()) {
      expect(tokens.colorCarPaint[s.paint], s.id).toMatch(/^#[0-9A-F]{6}$/i);
      expect(s.tags.length, s.id).toBeGreaterThan(0);
      for (const tag of s.tags) expect(cityIdValues as readonly string[], `${s.id} ${tag}`).toContain(tag);
    }
    for (const id of [tuning.cars.startCar, ...tuning.cars.startOwned, ...tuning.cars.parked.models]) expect(specs.has(id), id).toBe(true);
  });

  it('draws every class inside the body outline, details by class', () => {
    for (const s of specs.values()) {
      const parts = carShape(s.class, 5, 2, s.length_m);
      expect(paintHex(s.paint)).toBe(tokens.colorCarPaint[s.paint]);
      for (const r of parts.filter((p) => p.part !== 'shadow')) {
        expect(Math.min(r.x0, r.x1)).toBeGreaterThanOrEqual(-5);
        expect(Math.max(r.x0, r.x1)).toBeLessThanOrEqual(5);
        expect(Math.max(Math.abs(r.y0), Math.abs(r.y1))).toBeLessThanOrEqual(2);
      }
    }
    expect(carShape('taxi', 5, 2).some((r) => r.color === tokens.colorCarDetailTaxiSign)).toBe(true);
    expect(carShape('pickup', 5, 2).some((r) => r.color === tokens.colorCarDetailBed)).toBe(true);
    expect(carShape('hatchback', 5, 2).some((r) => r.part === 'stripe')).toBe(false);
  });

  it('draws micro cars as a scooter or a bicycle inside the outline, without lights', () => {
    const scooter = specs.get('kolobezka')!, bike = specs.get('kolo')!;
    expect(scooter.length_m).toBeLessThan(1.5);
    expect(bike.length_m).toBeGreaterThanOrEqual(1.5);
    const shapes = [scooter, bike].map((s) => {
      const hl = (s.length_m * tuning.carScale) / 2, hw = (s.width_m * tuning.carScale) / 2;
      const parts = carShape(s.class, hl, hw, s.length_m);
      for (const r of parts.filter((p) => p.part !== 'shadow')) {
        expect(Math.min(r.x0, r.x1), s.id).toBeGreaterThanOrEqual(-hl);
        expect(Math.max(r.x0, r.x1), s.id).toBeLessThanOrEqual(hl);
        expect(Math.max(Math.abs(r.y0), Math.abs(r.y1)), s.id).toBeLessThanOrEqual(hw);
      }
      expect(parts.some((p) => p.part === 'head' || p.part === 'tail' || p.part === 'glass'), s.id).toBe(false);
      // Two in-line wheels (plus the handlebar, also tyre-coloured) and a rider.
      expect(parts.filter((p) => p.part === 'tyre' && Math.abs(p.y0) < hw / 2).length, s.id).toBe(2);
      expect(parts.some((p) => p.part === 'cabin'), s.id).toBe(true);
      return parts.map((p) => [p.part, p.x0 / hl, p.y0 / hw]);
    });
    expect(shapes[0]).not.toEqual(shapes[1]);
  });
});

describe('parked models by city (specs/cars.md)', () => {
  const models = tuning.cars.parked.models;

  it('keeps every original model in list order for NYC', () => {
    const nyc = parkedPool(models, specs, 'nyc');
    expect(nyc).toEqual(['hatch_pip', 'muscle_brute', 'taxi_metro', 'pickup_hauler', 'm0_coupe']);
    expect(nyc).toEqual(models.filter((id) => specs.get(id)!.tags.includes('nyc')));
  });

  it('parks only prague-tagged cars in Prague', () => {
    const prague = parkedPool(models, specs, 'prague');
    expect(prague).toEqual(['hatch_pip', 'lidovka', 'kolobezka', 'kolo']);
    for (const id of prague) expect(specs.get(id)!.tags, id).toContain('prague');
  });

  it('has an empty pool for a city without tagged cars or without models', () => {
    expect(parkedPool(models, specs, 'nowhere')).toEqual([]);
    expect(parkedPool([], specs, 'nyc')).toEqual([]);
  });
});

describe('cars rules (P0)', () => {
  const start = (): { r: CarsRules; s: CarsState } => {
    const r = new CarsRules();
    return { r, s: r.init(carsConfig(tuning.cars, prices), 0) };
  };

  it('starts with the M0 coupe and nothing to do in the garage', () => {
    const { r, s } = start();
    expect(s).toEqual({ cash: 0, owned: ['m0_coupe'], driving: 'm0_coupe', stolen: false, thefts: 0 });
    expect(r.legalActions(s)).toEqual([]);
    expect(r.buyable(s)).toEqual([]);
    expect(r.result(s)).toBeNull();
  });

  it('marks a taken car as stolen and lets the player drive out of the garage with the own car', () => {
    const { r, s } = start();
    const a = r.apply(s, { by: 'player', op: 'board', car: 'taxi_metro', owner: 'npc' });
    expect(a.stolen).toBe(true);
    expect(r.legalActions(a)).toEqual([{ by: 'player', op: 'select', car: 'm0_coupe' }]);
    const b = r.apply(a, { by: 'player', op: 'select', car: 'm0_coupe' });
    expect(b).toMatchObject({ driving: 'm0_coupe', stolen: false, thefts: 1 });
  });

  it('rejects illegal actions', () => {
    const { r, s } = start();
    expect(() => r.apply(s, { by: 'player', op: 'board', car: 'taxi_metro', owner: 'player' })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'select', car: 'm0_coupe' })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'buy', car: 'hatch_pip' })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'buy', car: 'nope' })).toThrow();
  });

  it('buys with enough cash (API for M1-S11)', () => {
    const r = new CarsRules();
    const s = r.init({ ...carsConfig(tuning.cars, prices), cash: 16000 }, 0);
    // Every affordable car not owned, in catalogue order; M3 adds the cheap Prague cars.
    expect(r.buyable(s)).toEqual(expect.arrayContaining(['hatch_pip', 'taxi_metro']));
    for (const id of r.buyable(s)) expect(prices[id]!, id).toBeLessThanOrEqual(16000);
    expect(r.buyable(s)).not.toContain('m0_coupe');
    const b = r.apply(s, { by: 'player', op: 'buy', car: 'taxi_metro' });
    expect(b.cash).toBe(1000);
    expect(b.owned).toEqual(['m0_coupe', 'taxi_metro']);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };

describe.skipIf(!existsSync(pack))('parked cars and boarding in NYC', () => {
  let city: City;
  const chunks: ChunkData[] = [];
  beforeAll(async () => {
    city = await City.load(source);
    const cx = Math.floor(city.startX / city.chunkM), cy = Math.floor(city.startY / city.chunkM);
    for (const c of city.manifest.chunks) {
      if (Math.abs(c.x - cx) <= 2 && Math.abs(c.y - cy) <= 2) chunks.push(await prepareChunk(await source.read(chunkPath(c.x, c.y))));
    }
  });

  it('places parked cars deterministically at curbs, spaced apart', () => {
    let total = 0;
    for (const c of chunks) {
      const a = generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, city.id);
      const b = generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, city.id);
      expect(a).toEqual(b);
      expect(a.length).toBeLessThanOrEqual(tuning.cars.parked.perChunk);
      for (let i = 0; i < a.length; i++) {
        for (let j = i + 1; j < a.length; j++) expect(Math.hypot(a[i]!.x - a[j]!.x, a[i]!.y - a[j]!.y)).toBeGreaterThanOrEqual(tuning.cars.parked.minSpacingM);
        const hit = city.graph.nearest(a[i]!.x, a[i]!.y, 60, (e) => e.isGround);
        expect(hit).not.toBeNull();
        expect(hit!.dist).toBeLessThan(hit!.edge.width / 2);
      }
      total += a.length;
    }
    expect(total).toBeGreaterThan(10);
  });

  it('filters models by city without changing NYC; an empty pool parks nothing', () => {
    expect(city.id).toBe('nyc');
    // The pre-M3 list: every NYC model, unfiltered.
    const m1 = ['hatch_pip', 'muscle_brute', 'taxi_metro', 'pickup_hauler', 'm0_coupe'];
    const old = { ...tuning, cars: { ...tuning.cars, parked: { ...tuning.cars.parked, models: m1 } } } as unknown as Tuning;
    let total = 0;
    for (const c of chunks) {
      const now = generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, 'nyc');
      expect(now).toEqual(generateParked(city.graph, c.x, c.y, 1, old, specs, [], { x: 1e9, y: 1e9 }, 'nyc'));
      for (const p of now) expect(m1).toContain(p.carId);
      expect(generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, 'nowhere')).toEqual([]);
      total += now.length;
    }
    expect(total).toBeGreaterThan(10);
  });

  it('boards a parked car: new body with its parameters, old car stays parked, stolen event fires', () => {
    const d = new DriveWorld(city, specs.get(tuning.cars.startCar)!, tuning);
    const fleet = new CarFleet(d, specs, tuning, { id: 'g', x: d.car.x, y: d.car.y, heading: d.car.heading });
    for (const c of chunks) {
      d.addChunk(c);
      fleet.addChunk(c);
    }
    expect(fleet.parked.length).toBeGreaterThan(0);
    const target = fleet.parked[0]!;
    // Teleport next to it, at rest.
    d.spawn(target.x + 6 * Math.cos(target.heading + Math.PI / 2), target.y + 6 * Math.sin(target.heading + Math.PI / 2), target.heading);
    expect(boardCandidate(fleet.parked, d.car.x, d.car.y, tuning.cars.boardDistanceM)).toBe(target);
    expect(fleet.candidate()).toBe(target);
    expect(fleet.action(0)).toEqual({ kind: 'board', car: target });
    // Auto-throttle moves the car on: the button stays for action_hold_s while still close.
    d.car.body.setLinearVelocity({ x: 3, y: 0 });
    expect(fleet.candidate()).toBeNull();
    expect(fleet.action(tuning.cars.actionHoldS / 2)).toEqual({ kind: 'board', car: target });
    expect(fleet.action(tuning.cars.actionHoldS)?.kind).not.toBe('board');
    d.car.body.setLinearVelocity({ x: 0, y: 0 });
    const events: string[] = [];
    fleet.on('stolen', (e) => events.push(`stolen ${e.car}`));
    fleet.on('ownerQuip', (e) => events.push(`quip ${e.car}`));
    fleet.on('carChanged', (e) => events.push(`changed ${e.car}`));
    const before = fleet.parked.length;
    fleet.board(target);
    expect(events).toEqual([`stolen ${target.carId}`, `quip ${target.carId}`, `changed ${target.carId}`]);
    expect(fleet.state.stolen).toBe(true);
    expect(d.car.spec.id).toBe(target.carId);
    const spec = specs.get(target.carId)!;
    expect(d.car.halfLength).toBeCloseTo((spec.length_m * tuning.carScale) / 2);
    expect(d.car.spec.mass).toBe(spec.mass);
    expect(d.car.body.getMass()).toBeGreaterThan(spec.mass);
    expect(fleet.parked.length).toBe(before);
    const left = fleet.parked.find((p) => p.chunk === null)!;
    expect(left).toMatchObject({ carId: 'm0_coupe', owner: 'player' });
    // Back into the own car: not stolen any more.
    fleet.board(left);
    expect(fleet.state).toMatchObject({ driving: 'm0_coupe', stolen: false, thefts: 1 });
  });

  it('switches cars in the garage', () => {
    const d = new DriveWorld(city, specs.get(tuning.cars.startCar)!, tuning);
    const fleet = new CarFleet(d, specs, tuning, { id: 'g', x: d.car.x, y: d.car.y, heading: d.car.heading });
    expect(fleet.atGarage()).toBe(true);
    expect(fleet.action(0)).toEqual({ kind: 'garage' });
    fleet.state = { ...fleet.state, owned: ['m0_coupe', 'pickup_hauler'] };
    expect(fleet.canSelect('m0_coupe')).toBe(false);
    fleet.select('pickup_hauler');
    expect(d.car.spec.id).toBe('pickup_hauler');
    expect(d.spec.id).toBe('pickup_hauler');
    // A respawn keeps the car.
    d.spawn(city.startX, city.startY, city.startHeading);
    expect(d.car.spec.id).toBe('pickup_hauler');
  });
});
