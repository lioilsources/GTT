import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { parse } from 'yaml';
import { beforeAll, describe, expect, it } from 'vitest';

import { CarFleet } from '../src/cars/fleet';
import { boardCandidate, generateParked, parkedPool } from '../src/cars/parked';
import { carsConfig, CarsRules, type CarsState } from '../src/cars/rules';
import { carPrims } from '../src/cars/carTris';
import { carShape, paintHex, shapeKind, wheelLayout } from '../src/cars/shape';
import { saleOrder } from '../src/cars/ui';
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
      // The offroad spare wheel hangs off the tailgate (specs/cars.md).
      for (const r of parts.filter((p) => p.part !== 'shadow' && p.color !== tokens.colorCarDetailSpare)) {
        expect(Math.min(r.x0, r.x1)).toBeGreaterThanOrEqual(-5);
        expect(Math.max(r.x0, r.x1)).toBeLessThanOrEqual(5);
        expect(Math.max(Math.abs(r.y0), Math.abs(r.y1))).toBeLessThanOrEqual(2);
      }
    }
    expect(carShape('taxi', 5, 2).some((r) => r.color === tokens.colorCarDetailTaxiSign)).toBe(true);
    expect(carShape('pickup', 5, 2).some((r) => r.color === tokens.colorCarDetailBed)).toBe(true);
    expect(carShape('hatchback', 5, 2).some((r) => r.part === 'stripe')).toBe(false);
  });

  it('v2: every class and special variant has its own shape with its detail tokens (F-045)', () => {
    const variants: Array<[string, number]> = [
      ['mini', 3], ['hatchback', 4], ['sedan', 4.5], ['kombi', 4.9], ['coupe', 4.5], ['muscle', 5], ['supersport', 4.5],
      ['veteran', 5], ['offroad', 4.8], ['pickup', 5.4], ['van', 6], ['taxi', 5], ['limo', 8], ['bus', 12],
      ['micro', 1.2], ['micro', 1.8], ['special', 7], ['special', 3.2], ['special', 2.6]];
    const key = (cls: string, len: number): string =>
      JSON.stringify(carShape(cls, 5, 2, len, 3).map((r) => [r.part, r.color ?? '', r.x0, r.y0, r.x1, r.y1, r.poly ?? []]));
    const keys = variants.map(([c, l]) => key(c, l));
    expect(new Set(keys).size).toBe(variants.length);
    expect(shapeKind('special', 7)).toBe('foodtruck');
    expect(shapeKind('special', 5)).toBe('foodtruck');
    expect(shapeKind('special', 3.2)).toBe('trike');
    expect(shapeKind('special', 2.8)).toBe('trike');
    expect(shapeKind('special', 2.6)).toBe('rickshaw');
    const has = (cls: string, color: string, len = 0): boolean => carShape(cls, 5, 2, len, 3).some((r) => r.color === color);
    expect(has('kombi', tokens.colorCarDetailRoofRail)).toBe(true);
    expect(has('supersport', tokens.colorCarDetailSpoiler)).toBe(true);
    expect(has('veteran', tokens.colorCarDetailFender)).toBe(true);
    expect(has('offroad', tokens.colorCarDetailSpare)).toBe(true);
    expect(has('van', tokens.colorCarDetailCargoRoof)).toBe(true);
    expect(has('limo', tokens.colorCarDetailLimoPillar)).toBe(true);
    expect(has('bus', tokens.colorCarDetailBusRoofUnit)).toBe(true);
    expect(has('special', tokens.colorCarDetailAwningA, 7) && has('special', tokens.colorCarDetailAwningB, 7)).toBe(true);
    expect(has('special', tokens.colorCarDetailCanopy, 2.6)).toBe(true);
    // Veteran: narrow body, four fenders on the outer side over the wheels.
    const vet = carShape('veteran', 5, 2, 5, 3);
    expect(vet.find((r) => r.part === 'body')).toMatchObject({ y0: -1.6, y1: 1.6 });
    const fenders = vet.filter((r) => r.color === tokens.colorCarDetailFender);
    expect(fenders.map((r) => (r.x0 + r.x1) / 2).sort()).toEqual([-3, -3, 3, 3]);
    // Bus: no cabin; trike: narrowed nose polygon.
    expect(carShape('bus', 5, 2, 12).some((r) => r.part === 'cabin' && r.x0 < 4)).toBe(false);
    const trikeBody = carShape('special', 5, 2, 3.2).find((r) => r.part === 'body')!;
    expect(trikeBody.poly).toBeDefined();
  });

  it('v2: wheels by class (bus axles, one front wheel on trike and rickshaw)', () => {
    expect(wheelLayout('coupe', 5, 2, 3).map((w) => w.x)).toEqual([3, 3, -3, -3]);
    expect(wheelLayout('bus', 10, 2, 6).map((w) => w.x)).toEqual([6, 6, -7, -7]);
    for (const len of [3.2, 2.6]) {
      const w = wheelLayout('special', 5, 2, 3, len);
      expect(w).toHaveLength(3);
      expect(w.filter((x) => x.front)).toEqual([{ x: 3.75, y: 0, front: true, top: true }]);
    }
    expect(wheelLayout('special', 5, 2, 3, 7)).toHaveLength(4);
    expect(wheelLayout('micro', 1, 0.3, 0.6)).toEqual([]);
  });

  it('v2: decals stay inside a non-rectangular body (trike)', () => {
    const s = specs.get('spec_trike')!;
    const hl = (s.length_m * tuning.carScale) / 2, hw = (s.width_m * tuning.carScale) / 2;
    for (const decal of [1, 2, 3]) {
      const prims = carPrims(s, hl, hw, false, { decal }, undefined, hl * tuning.drive.axleOffset);
      const decals = prims.filter((p) => p.part === 'decal');
      expect(decals.length, `decal ${decal}`).toBeGreaterThan(0);
      for (const p of decals) {
        for (let i = 0; i < p.poly.length; i += 2) {
          const x = p.poly[i]!, y = Math.abs(p.poly[i + 1]!);
          // Inside the taper from (0.3 hl, hw) to (hl, 0.45 hw).
          const lim = x <= hl * 0.3 ? hw : hw - ((x - hl * 0.3) / (hl * 0.7)) * hw * 0.55;
          expect(y).toBeLessThanOrEqual(lim + 1e-9);
        }
      }
    }
  });

  it('v2: sale list sorted by city, class, price and id', () => {
    const order = saleOrder(specs.values(), ['m0_coupe'], 'prague').map((s) => s.id);
    expect(order).not.toContain('m0_coupe');
    const pragueCount = [...specs.values()].filter((s) => s.tags.includes('prague') && s.id !== 'm0_coupe').length;
    expect(order.slice(0, pragueCount).every((id) => specs.get(id)!.tags.includes('prague'))).toBe(true);
    const nyc = saleOrder(specs.values(), [], 'nyc');
    expect(nyc[0]!.class).toBe('mini');
    expect(nyc.slice(0, 3).map((s) => s.id)).toEqual(['mini_pebble', 'mini_dot', 'mini_bolt']);
    expect(nyc.at(-1)!.tags.includes('nyc')).toBe(false);
  });

  it('every part of every class is a proper rectangle (x0 < x1, y0 < y1)', () => {
    const classes = new Set([...specs.values()].map((s) => s.class));
    for (const cls of classes) {
      for (const lengthM of [1, 2, 4.5]) {
        for (const r of carShape(cls, 5, 2, lengthM)) {
          expect(r.x0, `${cls} ${r.part}`).toBeLessThan(r.x1);
          expect(r.y0, `${cls} ${r.part}`).toBeLessThan(r.y1);
        }
      }
    }
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
    // The M1 models come first, in their original order; later cars (M2) only append.
    expect(nyc.slice(0, 5)).toEqual(['hatch_pip', 'muscle_brute', 'taxi_metro', 'pickup_hauler', 'm0_coupe']);
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
      const a = generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, city.id, false);
      const b = generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, city.id, false);
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

  it('filters models by city; an empty pool parks nothing', () => {
    expect(city.id).toBe('nyc');
    const pool = parkedPool(tuning.cars.parked.models, specs, 'nyc');
    let total = 0;
    for (const c of chunks) {
      const now = generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, 'nyc', false);
      // Deterministic per chunk, and only models of the city's pool park there.
      expect(now).toEqual(generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, 'nyc', false));
      for (const p of now) expect(pool).toContain(p.carId);
      expect(generateParked(city.graph, c.x, c.y, 1, tuning, specs, [], { x: 1e9, y: 1e9 }, 'nowhere', false)).toEqual([]);
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
