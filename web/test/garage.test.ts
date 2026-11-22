import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { World } from 'planck';
import { parse } from 'yaml';
import { beforeAll, describe, expect, it } from 'vitest';

import { carPrims, carTris, parkedTris } from '../src/cars/carTris';
import { CarFleet } from '../src/cars/fleet';
import { Car } from '../src/drive/car';
import { ControlInput } from '../src/drive/controls';
import { DriveWorld } from '../src/drive/driveWorld';
import { GarageWorld } from '../src/garage/garage';
import { decalPolys, glowPoly, glowStrength, lookGlow, lookPaint, lookRim } from '../src/garage/looks';
import { garageConfig, GarageRules, partCounts, tunedSpec, type Levels } from '../src/garage/rules';
import type { CarSpec } from '../src/gen/schema';
import { tokens } from '../src/gen/tokens';
import { Tuning } from '../src/gen/tuning';
import { normalizeSave, saveConfig, composeSave, SAVE_VERSION } from '../src/loop/save';
import { Tris } from '../src/render/geometry';
import { rgba } from '../src/render/palette';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const specs = new Map<string, CarSpec>(
  readdirSync(join(root, 'content', 'cars')).map((f) => {
    const s = JSON.parse(readFileSync(join(root, 'content', 'cars', f), 'utf8')) as CarSpec;
    return [s.id, s];
  }),
);
const coupe = specs.get('m0_coupe')!;
const g = tuning.garage;

describe('tunedSpec (specs/garage.md "Účinek na jízdu")', () => {
  it('multiplies the catalog parameters by the level steps', () => {
    const s = tunedSpec(coupe, { engine: 2, tyres: 1, brakes: 3, weight: 2, drift: 1 }, g);
    expect(s.id).toBe(coupe.id);
    expect(s.power).toBeCloseTo(coupe.power * (1 + 2 * g.enginePowerStep) * (1 + 2 * g.weightPowerStep));
    expect(s.top_speed).toBeCloseTo(coupe.top_speed * (1 + 2 * g.engineTopStep));
    expect(s.grip_front).toBeCloseTo(coupe.grip_front * (1 + g.tyresStep));
    expect(s.grip_rear).toBeCloseTo(coupe.grip_rear * (1 + g.tyresStep));
    expect(s.brake).toBeCloseTo(coupe.brake * (1 + 3 * g.brakesStep));
    expect(s.mass).toBeCloseTo(coupe.mass * (1 - 2 * g.weightMassStep));
    expect(s.steer_speed).toBeCloseTo(coupe.steer_speed * (1 + 2 * g.weightSteerStep));
    expect(s.drift_bias).toBeCloseTo(coupe.drift_bias * (1 - g.driftStep));
    expect(coupe.power).toBe(specs.get('m0_coupe')!.power); // the catalog stays
  });

  it('is the catalog spec without levels and ignores slots a car does not have', () => {
    expect(tunedSpec(coupe, {}, g)).toBe(coupe);
    const kolo = specs.get('kolo')!;
    expect(kolo.tuning_slots).toEqual([]);
    expect(tunedSpec(kolo, { engine: 3 }, g)).toEqual(kolo);
  });
});

/** Fixed-step drive on an empty planck world: the same Car code DriveWorld steps. */
function drive(spec: CarSpec, frames: number, input: ControlInput, cruise: number, each: (car: Car, t: number) => boolean | void): Car {
  const world = new World({ gravity: { x: 0, y: 0 } });
  const car = new Car(world, spec, tuning.drive, 0, 0, 0, tuning.carScale);
  const step = 1 / tuning.drive.stepHz;
  for (let i = 0; i < frames; i++) {
    car.drive(input, step, cruise, tuning.speedMps.topDefault);
    world.step(step, tuning.drive.velocityIterations, tuning.drive.positionIterations);
    if (each(car, (i + 1) * step)) break;
  }
  return car;
}

function timeTo25(levels: Levels): number {
  const input = new ControlInput();
  input.throttle = 1;
  input.boost = true;
  let at = Infinity;
  drive(tunedSpec(coupe, levels, g), tuning.drive.stepHz * 30, input, tuning.speedMps.cruise, (car, t) => {
    if (car.speed >= 25) {
      at = t;
      return true;
    }
  });
  return at;
}

/**
 * Full lock at a held 15 m/s for 3 s: the turn radius (speed / yaw rate) at the end and the lateral
 * slip of both axles summed over the turn (metres slid sideways).
 */
function turn(levels: Levels): { radius: number; slip: number } {
  const spec = tunedSpec(coupe, levels, g);
  const input = new ControlInput();
  const hz = tuning.drive.stepHz;
  // Up to 15 m/s straight (auto-throttle to the cruise argument), then full steer for 3 s.
  const car = drive(spec, hz * 20, input, 15, (c) => c.speed >= 14.9);
  const world = car.world, step = 1 / hz;
  input.steer = 1;
  let slip = 0;
  for (let i = 0; i < hz * 3; i++) {
    car.drive(input, step, 15, tuning.speedMps.topDefault);
    world.step(step, tuning.drive.velocityIterations, tuning.drive.positionIterations);
    slip += (Math.abs(car.frontSlip) + Math.abs(car.rearSlip)) * step;
  }
  return { radius: car.speed / Math.abs(car.body.getAngularVelocity()), slip };
}

describe('tuning changes the drive measurably (acceptance, specs/garage.md)', () => {
  it('engine 3 reaches 25 m/s at least 10 % sooner', () => {
    const base = timeTo25({}), tuned = timeTo25({ engine: 3 });
    console.info(`[garage acceptance] 0→25 m/s: stock ${base.toFixed(3)} s, engine 3 ${tuned.toFixed(3)} s (${(100 * (1 - tuned / base)).toFixed(1)} % sooner)`);
    expect(Number.isFinite(base)).toBe(true);
    expect(tuned).toBeLessThanOrEqual(base * 0.9);
  });

  it('tyres 3 hold a full turn at 15 m/s with at least 5 % smaller radius or lateral slip', () => {
    const base = turn({}), tuned = turn({ tyres: 3 });
    console.info(`[garage acceptance] full turn at 15 m/s for 3 s: radius stock ${base.radius.toFixed(2)} m, tyres 3 ${tuned.radius.toFixed(2)} m ` +
      `(${(100 * (1 - tuned.radius / base.radius)).toFixed(1)} % smaller); lateral slip ${base.slip.toFixed(3)} → ${tuned.slip.toFixed(3)} m ` +
      `(${(100 * (1 - tuned.slip / base.slip)).toFixed(1)} % smaller)`);
    expect(base.slip).toBeGreaterThan(0);
    // At 15 m/s full lock is steering-limited (same radius); the grip shows in the slip (spec: "nebo menší boční skluz").
    expect(tuned.radius <= base.radius * 0.95 || tuned.slip <= base.slip * 0.95).toBe(true);
    expect(tuned.radius).toBeLessThanOrEqual(base.radius + 1e-6);
  });

  it('weather grip multiplies on top of the tyres', () => {
    const spec = tunedSpec(coupe, { tyres: 3 }, g);
    const world = new World({ gravity: { x: 0, y: 0 } });
    const car = new Car(world, spec, tuning.drive, 0, 0, 0, tuning.carScale);
    car.gripScale = tuning.weather.rainGrip;
    // The axle cap is grip × gripScale: rain on tyres 3 is still above rain on stock tyres.
    expect(spec.grip_front * car.gripScale).toBeGreaterThan(coupe.grip_front * tuning.weather.rainGrip);
    expect(spec.grip_front * car.gripScale).toBeCloseTo(coupe.grip_front * (1 + 3 * g.tyresStep) * tuning.weather.rainGrip);
  });
});

describe('garage module and world (specs/garage.md)', () => {
  const rules = new GarageRules();
  const cfg = garageConfig(g, specs.values());

  it('config: every catalog car with its slots, choices from the tokens', () => {
    expect(Object.keys(cfg.cars).sort()).toEqual([...specs.keys()].sort());
    expect(cfg.cars['kolo']).toEqual([]);
    expect(cfg.parts).toEqual(partCounts());
    expect(cfg.parts['paint']).toBe(1 + tokens.colorGaragePaints.length);
    expect(cfg.prices['engine']).toEqual(g.priceEngine);
  });

  it('legal actions: load, upgrades by car id, then looks; illegal buys throw', () => {
    const s = rules.init(cfg, 0);
    const legal = rules.legalActions(s);
    expect(legal[0]).toMatchObject({ op: 'load' });
    const ups = legal.filter((a) => a.op === 'upgrade').map((a) => (a as { car: string }).car);
    expect(ups).toEqual([...ups].sort());
    expect(() => rules.apply(s, { by: 'player', op: 'upgrade', car: 'kolo', slot: 'engine', cash: 1e6 })).toThrow();
    expect(() => rules.apply(s, { by: 'player', op: 'upgrade', car: 'm0_coupe', slot: 'engine', cash: 10 })).toThrow();
    expect(() => rules.apply(s, { by: 'player', op: 'look', car: 'm0_coupe', part: 'paint', value: 0, cash: 0 })).toThrow();
    expect(() => rules.apply(s, { by: 'player', op: 'load', upgrades: { m0_coupe: { engine: 1.5 } }, looks: {} })).toThrow();
    expect(() => rules.apply(s, { by: 'player', op: 'load', upgrades: [], looks: {} })).toThrow();
  });

  it('pays from the cars cash, back to stock is free', () => {
    let cash = 2500;
    const w = new GarageWorld(tuning, specs.values(), { get: () => cash, set: (c) => (cash = c) });
    expect(w.canUpgrade('m0_coupe', 'engine')).toBe(true);
    expect(w.upgrade('m0_coupe', 'engine')).toBe(g.priceEngine[0]);
    expect(cash).toBe(2500 - g.priceEngine[0]!);
    expect(w.canUpgrade('m0_coupe', 'engine')).toBe(false);
    expect(w.upgrade('m0_coupe', 'engine')).toBeNull();
    expect(w.setLook('m0_coupe', 'paint', 3)).toBe(g.lookPricePaint);
    cash = 0;
    expect(w.canLook('m0_coupe', 'decal', 1)).toBe(false);
    expect(w.setLook('m0_coupe', 'paint', 0)).toBe(0);
    expect(w.state.looks).toEqual({});
    expect(w.levels('m0_coupe')).toEqual({ engine: 1 });
    w.load({ m0_coupe: { engine: '1' } }, {});
    expect(w.state.upgrades).toEqual({});
  });
});

describe('save format 5 (specs/save.md v4)', () => {
  const cfg = saveConfig(tuning, 'nyc', [...specs.keys()]);
  it('round-trips upgrades and looks with sorted keys', () => {
    const s = composeSave(cfg, {
      cash: 10, cars: ['m0_coupe'], car: 'm0_coupe', stamps: [], best: {}, plays: {},
      upgrades: { m0_coupe: { tyres: 2, engine: 1 } }, looks: { m0_coupe: { paint: 3 } },
    });
    expect(s.version).toBe(SAVE_VERSION);
    expect(SAVE_VERSION).toBe(5);
    expect(JSON.stringify(s.upgrades)).toBe('{"m0_coupe":{"engine":1,"tyres":2}}');
    expect(normalizeSave(cfg, JSON.parse(JSON.stringify(s)))).toEqual(s);
  });
});

describe('looks drawing (specs/garage.md "Kreslení")', () => {
  it('paint, rims, glow and smoke colours come from the tokens', () => {
    expect(lookPaint(coupe, {})).toBe(tokens.colorCarPaint[coupe.paint]);
    expect(lookPaint(coupe, { paint: 1 })).toBe(tokens.colorGaragePaints[0]);
    expect(lookRim({ wheels: 2 })).toBe(tokens.colorGarageWheels[2]);
    expect(lookGlow({})).toBeNull();
    expect(lookGlow({ glow: 2 })).toBe(tokens.colorGarageGlow[1]);
    expect(glowStrength(false, false, g.glowDay)).toBe(g.glowDay);
    expect(glowStrength(true, false, g.glowDay)).toBe(1);
    expect(glowStrength(false, true, g.glowDay)).toBe(1);
  });

  it('paints the body and glass, decal over the details and under the lights', () => {
    const hl = 2.5, hw = 1;
    const muscle = specs.get('muscle_brute')!;
    const prims = carPrims(muscle, hl, hw, false, { paint: 3, decal: 1 });
    const body = prims.find((p) => p.part === 'body')!;
    expect(body.color).toEqual(rgba(tokens.colorGaragePaints[2]!));
    const glass = prims.find((p) => p.part === 'glass')!.color;
    const white = rgba(tokens.colorUiText);
    expect(glass[0]).toBeCloseTo(body.color[0] * 0.88 + white[0] * 0.12);
    const idx = (part: string): number[] => prims.map((p, i) => (p.part === part ? i : -1)).filter((i) => i >= 0);
    expect(Math.min(...idx('decal'))).toBeGreaterThan(Math.max(...idx('detail')));
    expect(Math.max(...idx('decal'))).toBeLessThan(Math.min(...idx('head')));
    // Catalog drawing without a look.
    expect(carPrims(muscle, hl, hw, false).some((p) => p.part === 'decal')).toBe(false);
  });

  it('decals stay on the body; stripes at ±0.22 hw, flames to 0.35 hl from the nose', () => {
    const b = { x0: -2.5, y0: -1, x1: 2.5, y1: 1 };
    for (const d of [1, 2, 3]) {
      const polys = decalPolys(d, b);
      expect(polys.length, String(d)).toBeGreaterThan(0);
      for (const p of polys) {
        for (let i = 0; i < p.length; i += 2) {
          expect(Math.abs(p[i]!)).toBeLessThanOrEqual(2.5 + 1e-9);
          expect(Math.abs(p[i + 1]!)).toBeLessThanOrEqual(1 + 1e-9);
        }
      }
    }
    const stripes = decalPolys(1, b);
    expect(stripes.map((p) => (p[1]! + p[5]!) / 2).sort()).toEqual([-0.22, 0.22].map((v) => expect.closeTo(v, 6)));
    const flames = decalPolys(2, b);
    expect(flames.length).toBe(3);
    expect(Math.min(...flames.flatMap((p) => p.filter((_, i) => i % 2 === 0)))).toBeCloseTo(0.35 * 2.5);
    expect(decalPolys(0, b)).toEqual([]);
  });

  it('underglow is a rounded rectangle glow_margin_m past the car, only with a glow', () => {
    const p = glowPoly(2, 1, g.glowMarginM);
    const xs = p.filter((_, i) => i % 2 === 0), ys = p.filter((_, i) => i % 2 === 1);
    expect(Math.max(...xs)).toBeCloseTo(2 + g.glowMarginM);
    expect(Math.max(...ys)).toBeCloseTo(1 + g.glowMarginM);
    const own = { carId: 'm0_coupe', owner: 'player' as const, x: 0, y: 0, heading: 0, chunk: null };
    const npc = { ...own, owner: 'npc' as const };
    const plain = parkedTris([npc], specs, tuning.carScale, tuning.drive.axleOffset, 0.1).vertexCount;
    const looked = parkedTris([own], specs, tuning.carScale, tuning.drive.axleOffset, 0.1, undefined,
      (q) => (q.owner === 'player' ? { glow: 1, decal: 3 } : null), { margin: g.glowMarginM, strength: 1 }).vertexCount;
    expect(looked).toBeGreaterThan(plain);
    const t = new Tris();
    carTris(t, coupe, 2, 1, 1, 0, 0, 0, 0, false, true, true, undefined, { wheels: 1 });
    const rim = rgba(tokens.colorGarageWheels[1]!);
    expect(t.col.some((_, i) => i % 4 === 0 && t.col[i] === rim[0] && t.col[i + 1] === rim[1])).toBe(true);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };

describe.skipIf(!existsSync(pack))('upgrades build the own car only (specs/garage.md)', () => {
  let city: City;
  beforeAll(async () => {
    city = await City.load(source);
    void chunkPath;
  });

  it('own car is tuned, rebuilt in place at rest; a stolen car drives by the catalog', () => {
    const d = new DriveWorld(city, coupe, tuning);
    const fleet = new CarFleet(d, specs, tuning, { id: 'g', x: d.car.x, y: d.car.y, heading: d.car.heading });
    fleet.levelsOf = (id) => (id === 'm0_coupe' ? { engine: 3, tyres: 2 } : {});
    d.car.body.setLinearVelocity({ x: 5, y: 0 });
    const x = d.car.x, y = d.car.y;
    fleet.rebuild();
    expect(d.car.spec.power).toBeCloseTo(coupe.power * (1 + 3 * g.enginePowerStep));
    expect(d.car.x).toBeCloseTo(x);
    expect(d.car.y).toBeCloseTo(y);
    expect(d.car.speed).toBe(0);
    // A respawn keeps the tuned body.
    d.spawn(city.startX, city.startY, city.startHeading);
    expect(d.car.spec.grip_front).toBeCloseTo(coupe.grip_front * (1 + 2 * g.tyresStep));
    // Board a stranger's car: catalog parameters, even of a model the player owns too.
    const p = { carId: 'm0_coupe', owner: 'npc' as const, x: d.car.x + 20, y: d.car.y, heading: 0, chunk: null };
    fleet.parked.push(p);
    fleet.board(p);
    expect(fleet.state.stolen).toBe(true);
    expect(d.car.spec.power).toBe(coupe.power);
  });
});
