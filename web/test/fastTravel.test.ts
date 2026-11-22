import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { create, toBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld } from '../src/drive/driveWorld';
import { carIdValues, minigameCatalog } from '../src/gen/ids';
import {
  EdgeSchema, GraphSchema, LandmarkSchema, LandmarksSchema, ManifestSchema, NodeSchema, RoadClass, SpawnSchema, SpotSchema, SpotsSchema,
} from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { composeSave, freshSave, normalizeSave, saveConfig, SaveRules } from '../src/loop/save';
import { overlays, PauseGate, pausingOverlays } from '../src/pause';
import { carPose, PedestrianWorld } from '../src/peds/pedestrians';
import { phoneAppIds } from '../src/phone/phone';
import { canonical, rulesModules } from '../src/rules/vectors';
import { moveTo, stationInReach, stationsOf, taxiChoices, taxiTargets, travelOffered, TravelWorld } from '../src/travel/fast';
import { metroFare, taxiFare, travelConfig, travelDistDm, TravelRules, type TravelAction, type TravelConfig } from '../src/travel/rules';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const car = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;

afterEach(() => overlays.clear());

const cfg: TravelConfig = { stations: ['a', 'b', 'c'], fareBase: 30, farePerKm: 4, taxiBase: 60, taxiPerKm: 25 };
const p = (a: Record<string, unknown>): TravelAction => ({ by: 'player', ...a }) as TravelAction;

describe('travel rules (specs/travel.md)', () => {
  it('fares: base + distDm × perKm ÷ 10000, integer division', () => {
    expect(metroFare(cfg, 0)).toBe(30);
    expect(metroFare(cfg, 24999)).toBe(39);
    expect(metroFare(cfg, 25000)).toBe(40);
    expect(taxiFare(cfg, 0)).toBe(60);
    expect(taxiFare(cfg, 42345)).toBe(165);
    expect(metroFare({ fareBase: 0, farePerKm: 4 }, 2499)).toBe(0);
  });

  it('distDm: floor(sqrt) of rounded whole dm', () => {
    expect(travelDistDm(0, 0, 3, 4)).toBe(50);
    expect(travelDistDm(0.04, 0, 0.16, 0)).toBe(2); // 0 dm → 2 dm
    expect(travelDistDm(0, 0, 1, 1)).toBe(14);
  });

  it('config from tuning', () => {
    const t = tuning.travel;
    expect(travelConfig(t, ['x'])).toEqual({ stations: ['x'], fareBase: t.fareBase, farePerKm: t.farePerKm, taxiBase: t.taxiBase, taxiPerKm: t.taxiPerKm });
  });

  it('init, load (unknown and duplicates drop), unlock, legalActions', () => {
    const r = new TravelRules();
    let s = r.init(cfg, 5);
    expect(s).toEqual({ unlocked: [], paid: 0, last: { op: '', amount: 0 } });
    s = r.apply(s, p({ op: 'load', unlocked: ['c', 'zz', 'a', 'c'] }));
    expect(s.unlocked).toEqual(['c', 'a']);
    expect(r.legalActions(s)).toEqual([{ by: 'player', op: 'load', unlocked: [] }, { by: 'player', op: 'unlock', station: 'b' }]);
    s = r.apply(s, p({ op: 'unlock', station: 'b' }));
    expect(s.unlocked).toEqual(['c', 'a', 'b']);
    expect(r.apply(s, p({ op: 'unlock', station: 'a' })).unlocked).toEqual(['c', 'a', 'b']);
    expect(r.result(s)).toBeNull();
  });

  it('metro and taxi pay into paid/last; the next free action clears last', () => {
    const r = new TravelRules();
    let s = r.apply(r.init(cfg, 0), p({ op: 'load', unlocked: ['a', 'b'] }));
    s = r.apply(s, p({ op: 'metro', from: 'a', to: 'b', distDm: 25000, cash: 40 }));
    expect([s.paid, s.last]).toEqual([40, { op: 'metro', amount: 40 }]);
    s = r.apply(s, p({ op: 'taxi', distDm: 0, cash: 60 }));
    expect([s.paid, s.last]).toEqual([100, { op: 'taxi', amount: 60 }]);
    s = r.apply(s, p({ op: 'unlock', station: 'c' }));
    expect(s.last).toEqual({ op: '', amount: 0 });
    expect(s.paid).toBe(100);
  });

  it('illegal: unknown station, locked or equal ends, negative values, short cash, unknown op, by ≠ player', () => {
    const r = new TravelRules();
    const s = r.apply(r.init(cfg, 0), p({ op: 'load', unlocked: ['a', 'b'] }));
    const bad = [
      { by: 'player', op: 'unlock', station: 'zz' },
      { by: 'player', op: 'metro', from: 'a', to: 'c', distDm: 10, cash: 100 },
      { by: 'player', op: 'metro', from: 'a', to: 'a', distDm: 10, cash: 100 },
      { by: 'player', op: 'metro', from: 'a', to: 'b', distDm: -1, cash: 100 },
      { by: 'player', op: 'metro', from: 'a', to: 'b', distDm: 10, cash: -1 },
      { by: 'player', op: 'metro', from: 'a', to: 'b', distDm: 0, cash: 29 },
      { by: 'player', op: 'taxi', distDm: 0, cash: 59 },
      { by: 'player', op: 'taxi', distDm: -5, cash: 1000 },
      { by: 'player', op: 'taxi', distDm: 1.5, cash: 1000 },
      { by: 'player', op: 'fly' },
      { by: 'ai', op: 'taxi', distDm: 0, cash: 1000 },
    ];
    for (const a of bad) expect(() => r.apply(s, a as unknown as TravelAction), JSON.stringify(a)).toThrow();
  });

  it('registered for vectors with specVersion 1; save rules at specVersion 4', () => {
    expect(rulesModules['travel']!().specVersion).toBe(1);
    expect(rulesModules['travel']!().id).toBe('travel');
    expect(new SaveRules().specVersion).toBe(4);
  });
});

// ---------- synthetic city: one straight road west–east, two minigame spots, three stations, landmarks
const gz = <D extends DescMessage>(schema: D, m: MessageShape<D>): Uint8Array => new Uint8Array(gzipSync(toBinary(schema, m)));
const spot = (id: string, kind: string, x: number, minigame = '') =>
  create(SpotSchema, { id, kind, name: `${id} name`, x: x * 10, y: 0, edge: 0, parkX: x * 10, parkY: 0, parkHeading: 0, minigame });
const spots = [
  spot('st_w', 'subway', -300),
  spot('bar', 'bar', -100, 'oko'),
  spot('st_c', 'subway', 100),
  spot('pier', 'pier', 200, 'sipky'),
  spot('garage', 'garage', 250),
  spot('st_e', 'subway', 500),
];
const landmark = (id: string, x: number, y: number, hero: boolean) => create(LandmarkSchema, { id, name: `${id} name`, x: x * 10, y: y * 10, hero });

async function travelCity(): Promise<City> {
  const files: Record<string, Uint8Array> = {
    'manifest.pb': gz(ManifestSchema, create(ManifestSchema, {
      formatVersion: 1, cityId: 'test', chunkM: 256, driveSide: 'right', units: 'metric',
      start: create(SpawnSchema, { x: 0, y: 0, headingRad: 0 }),
    })),
    'graph.pb': gz(GraphSchema, create(GraphSchema, {
      names: [''],
      nodes: [create(NodeSchema, { x: -8000, y: 0 }), create(NodeSchema, { x: 8000, y: 0 })],
      edges: [create(EdgeSchema, { from: 0, to: 1, points: [-8000, 0, 8000, 0], class: RoadClass.PRIMARY, lanes: 4, oneway: 0, kept: true, widthM: 42 })],
    })),
    'landmarks.pb': gz(LandmarksSchema, create(LandmarksSchema, {
      items: [landmark('tower', 30, 20, true), landmark('statue', 40, 10, false), landmark('far_hero', 0, 5000, true)],
    })),
    'spots.pb': gz(SpotsSchema, create(SpotsSchema, { items: spots })),
  };
  return City.load({
    read: async (f) => {
      const b = files[f];
      if (!b) throw new Error(f);
      return b;
    },
  });
}

describe('fast travel in the world (synthetic city)', () => {
  let city: City;
  beforeAll(async () => {
    city = await travelCity();
  });
  const tr = tuning.travel;
  const wallet = (cash: number) => {
    const w = { cash, get: () => w.cash, set: (c: number) => (w.cash = c) };
    return w;
  };

  it('stations = subway spots in spots.pb order', () => {
    expect(stationsOf(city.spots.items).map((s) => s.id)).toEqual(['st_w', 'st_c', 'st_e']);
    expect(stationsOf(city.spots.items)[1]).toMatchObject({ x: 100, y: 0, name: 'st_c name' });
  });

  it('unlock by passing: layer 0 within travel.unlock_m, once; already unlocked stays', () => {
    const w = new TravelWorld(stationsOf(city.spots.items), tuning, wallet(0));
    expect(w.pass(100 + tr.unlockM + 1, 0, 0, tr.unlockM)).toEqual([]);
    expect(w.pass(100 + tr.unlockM - 1, 0, 1, tr.unlockM)).toEqual([]);
    expect(w.pass(100 + tr.unlockM - 1, 0, 0, tr.unlockM).map((s) => s.id)).toEqual(['st_c']);
    expect(w.pass(100, 0, 0, tr.unlockM)).toEqual([]);
    expect(w.pass(-300, 0, 0, tr.unlockM).map((s) => s.id)).toEqual(['st_w']);
    expect(w.unlocked).toEqual(['st_c', 'st_w']);
    // The save loads back through `load` (unknown stations drop).
    const w2 = new TravelWorld(stationsOf(city.spots.items), tuning, wallet(0));
    w2.load(['st_w', 'gone', 'st_w']);
    expect(w2.unlocked).toEqual(['st_w']);
  });

  it('"Metro": only at an unlocked station with the "Hrát" conditions', () => {
    const l = tuning.loop;
    const w = new TravelWorld(stationsOf(city.spots.items), tuning, wallet(0));
    expect(w.stationAt(100, 0, 0, 0, l)).toBeNull(); // locked
    w.load(['st_c']);
    expect(w.stationAt(100 + l.spotRadiusM - 1, 0, 0, 0, l)?.id).toBe('st_c');
    expect(w.stationAt(100 + l.spotRadiusM + 1, 0, 0, 0, l)).toBeNull();
    expect(w.stationAt(100, 0, l.stopSpeedMps + 0.1, 0, l)).toBeNull();
    expect(w.stationAt(100, 0, 0, 1, l)).toBeNull();
    expect(stationInReach(w.station('st_c')!, 100, 0, 0, 0, l)).toBe(true);
  });

  it('metro card: other unlocked stations in unlock order with fares, short cash greyed; the card pauses', () => {
    const cash = wallet(0);
    const w = new TravelWorld(stationsOf(city.spots.items), tuning, cash);
    w.load(['st_e', 'st_c', 'st_w']);
    const fe = metroFare(w.config, 4000), fw = metroFare(w.config, 4000);
    cash.cash = Math.min(fe, fw);
    const ch = w.metroChoices('st_c');
    expect(ch.map((c) => [c.point.id, c.distDm, c.fare])).toEqual([['st_e', 4000, fe], ['st_w', 4000, fw]]);
    expect(ch.every((c) => c.affordable)).toBe(true);
    cash.cash = fe - 1;
    expect(w.metroChoices('st_c').map((c) => c.affordable)).toEqual([false, false]);
    expect(w.anyLocked).toBe(false);
    // The card and the line card pause the world (specs/pause.md).
    expect(pausingOverlays).toContain('travel');
    const gate = new PauseGate(overlays);
    const release = overlays.open('travel');
    expect(gate.frame(1 / 60, null)).toBe(0);
    release();
    expect(gate.frame(1 / 60, null)).toBeCloseTo(1 / 60);
  });

  it('metro and taxi take the fare from the cars-state cash; not enough = null, cash unchanged', () => {
    const cash = wallet(1000);
    const w = new TravelWorld(stationsOf(city.spots.items), tuning, cash);
    w.load(['st_w', 'st_e']);
    const fare = metroFare(w.config, 8000);
    expect(w.metro('st_w', 'st_e')).toBe(fare);
    expect(cash.cash).toBe(1000 - fare);
    expect(w.metro('st_w', 'st_c')).toBeNull(); // locked
    cash.cash = fare - 1;
    expect(w.metro('st_e', 'st_w')).toBeNull();
    expect(cash.cash).toBe(fare - 1);
    cash.cash = 500;
    expect(w.taxi(1234)).toBe(taxiFare(w.config, 1234));
    expect(cash.cash).toBe(500 - taxiFare(w.config, 1234));
  });

  it('taxi targets: minigame spots, then hero landmarks on the nearest kept road', () => {
    const tg = taxiTargets(city.spots.items, minigameCatalog, city.graph, city.landmarks.items, tuning.minigames.taxi.destSearchM);
    expect(tg.map((x) => `${x.kind}:${x.id}`)).toEqual(['spot:bar', 'spot:pier', 'landmark:tower']);
    const tower = tg[2]!;
    expect(tower.x).toBeCloseTo(30);
    expect(tower.y).toBeCloseTo(0);
    expect(tower.heading).toBeCloseTo(0);
  });

  it('taxi list: sorted by distance from the car, fare per target, short cash greyed', () => {
    const tg = taxiTargets(city.spots.items, minigameCatalog, city.graph, city.landmarks.items, tuning.minigames.taxi.destSearchM);
    const c = travelConfig(tuning.travel, []);
    const list = taxiChoices(tg, 150, 0, taxiFare(c, 1200), c);
    expect(list.map((x) => x.point.id)).toEqual(['pier', 'tower', 'bar']);
    expect(list.map((x) => x.distDm)).toEqual([500, 1200, 2500]);
    expect(list.map((x) => x.fare)).toEqual([taxiFare(c, 500), taxiFare(c, 1200), taxiFare(c, 2500)]);
    expect(list.map((x) => x.affordable)).toEqual([true, true, taxiFare(c, 2500) <= taxiFare(c, 1200)]);
    // Ties keep the list order (spots, then landmarks).
    const tie = taxiChoices([{ id: 'x', name: 'x', x: 10, y: 0, heading: 0 }, { id: 'y', name: 'y', x: -10, y: 0, heading: 0 }], 0, 0, 0, c);
    expect(tie.map((x) => x.point.id)).toEqual(['x', 'y']);
    expect(tie.every((x) => !x.affordable || x.fare === 0)).toBe(true);
  });

  it('not offered while wanted, during a minigame or the Taxi shift; Taxi in the phone grid between Map and Garage', () => {
    expect(travelOffered({ busy: false, inWorldGame: false, wanted: 0 })).toBe(true);
    expect(travelOffered({ busy: false, inWorldGame: false, wanted: 1 })).toBe(false);
    expect(travelOffered({ busy: true, inWorldGame: false, wanted: 0 })).toBe(false);
    expect(travelOffered({ busy: false, inWorldGame: true, wanted: 0 })).toBe(false);
    expect(phoneAppIds.slice(0, 4)).toEqual(['feed', 'map', 'taxi', 'garage']);
  });

  it('the move: car at rest on the parking point facing parkHeading, layer 0; traffic, roadblock and pedestrians reset', () => {
    const drive = new DriveWorld(city, car, tuning);
    drive.spawn(-500, 0, 0);
    drive.input.throttle = 1;
    for (let i = 0; i < 240; i++) drive.update(1 / 60);
    expect(drive.car.speed).toBeGreaterThan(1);
    expect(drive.traffic!.cars.length).toBeGreaterThan(0);
    const peds = new PedestrianWorld(city, tuning);
    peds.update(1 / 60, [carPose(drive.car)], 200, false);
    expect(peds.peds.length).toBeGreaterThan(0);
    let cleared = 0;
    const target = { id: 'st_e', name: 'E', x: 500, y: 0, heading: Math.PI };
    moveTo({ drive, peds, police: { clearRoadblock: () => void cleared++ } }, target);
    expect(drive.car.x).toBeCloseTo(500);
    expect(drive.car.y).toBeCloseTo(0);
    expect(drive.car.heading).toBeCloseTo(Math.PI);
    expect(drive.car.speed).toBe(0);
    expect(drive.car.layer).toBe(0);
    expect(drive.traffic?.cars.length ?? 0).toBe(0);
    expect(peds.peds.length).toBe(0);
    expect(cleared).toBe(1);
  });
});

describe('save v3 (specs/save.md v2)', () => {
  const sc = saveConfig(tuning, 'nyc', carIdValues);
  const v2 = {
    version: 2, cityId: 'nyc', cash: 300, cars: ['m0_coupe'], car: 'm0_coupe', stamps: [], best: {}, plays: {},
    feed: { prefs: {}, visits: {}, districts: [] }, npc: { vibe: {}, contacts: [], recent: [] }, settings: { scheme: 'b', night: false },
  };

  it('fresh save is version 5 with no stations', () => {
    expect(freshSave(sc)).toMatchObject({ version: 5, stations: [] });
  });

  it('migration 2 → 3: everything kept, stations = [] (even when a v2 save carries some)', () => {
    const s = normalizeSave(sc, v2);
    expect(s.version).toBe(5);
    expect([s.cash, s.settings.scheme, s.stations]).toEqual([300, 'b', []]);
    expect(normalizeSave(sc, { ...v2, stations: ['subway_times_sq'] }).stations).toEqual([]);
  });

  it('v3: stations without duplicates (first occurrence), missing = [], wrong type = fresh', () => {
    expect(normalizeSave(sc, { ...v2, version: 3, stations: ['b', 'a', 'b'] }).stations).toEqual(['b', 'a']);
    expect(normalizeSave(sc, { ...v2, version: 3 }).stations).toEqual([]);
    expect(normalizeSave(sc, { ...v2, version: 3, stations: [1] })).toEqual(freshSave(sc));
    expect(normalizeSave(sc, { ...v2, version: 6 })).toEqual(freshSave(sc));
  });

  it('round trip of a v3 save through JSON is exact', () => {
    const s = composeSave(sc, {
      cash: 77, cars: ['m0_coupe'], car: 'm0_coupe', stamps: ['district:soho'], best: {}, plays: { x: 1 }, stations: ['subway_fulton', 'subway_w4'],
    });
    const back = normalizeSave(sc, JSON.parse(JSON.stringify(s)));
    expect(canonical(back)).toBe(canonical(s));
    expect(back.stations).toEqual(['subway_fulton', 'subway_w4']);
  });
});
